"""Publish every doc_id in data/regulations/sources.json onto the RabbitMQ
ingest queue, so ingest-worker (re)indexes each document.

Uses the RabbitMQ management HTTP API rather than an AMQP client library,
so this script has zero third-party dependencies and runs with any
system python3.

Usage: python3 scripts/ingest_corpus.py
"""
import base64
import json
import os
import urllib.request
from pathlib import Path

MANAGEMENT_URL = os.environ.get("RABBITMQ_MANAGEMENT_URL", "http://localhost:15672")
USERNAME = os.environ.get("RABBITMQ_USERNAME", "guest")
PASSWORD = os.environ.get("RABBITMQ_PASSWORD", "guest")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "regdesk.ingest")
DEFAULT_VHOST = "%2f"  # URL-encoded default vhost "/"

SOURCES_PATH = Path(__file__).resolve().parent.parent / "data" / "regulations" / "sources.json"


def _publish(doc_id: str) -> None:
    url = f"{MANAGEMENT_URL}/api/exchanges/{DEFAULT_VHOST}/amq.default/publish"
    body = json.dumps(
        {
            "properties": {"delivery_mode": 2},  # persistent, survives a broker restart
            "routing_key": QUEUE_NAME,
            "payload": doc_id,
            "payload_encoding": "string",
        }
    ).encode("utf-8")

    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/json")
    credentials = base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()
    request.add_header("Authorization", f"Basic {credentials}")

    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 200:
            raise RuntimeError(f"Failed to publish '{doc_id}': HTTP {response.status}")


def main() -> None:
    sources = json.loads(SOURCES_PATH.read_text(encoding="utf-8"))
    doc_ids = [doc["doc_id"] for doc in sources["documents"]]

    for doc_id in doc_ids:
        _publish(doc_id)
        print(f"Queued '{doc_id}'")

    print(f"Queued {len(doc_ids)} document(s) onto '{QUEUE_NAME}' via {MANAGEMENT_URL}")


if __name__ == "__main__":
    main()
