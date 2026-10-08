"""Tests for Settings' RabbitMQ URL composition (app.config).

Kubernetes (via the RabbitMQ Cluster Operator's Secret) supplies discrete
host/user/password env vars rather than one connection string; docker-compose
and local dev supply a ready-made URL directly. Both paths must work.
"""
from app.config import Settings


def test_explicit_rabbitmq_url_is_used_as_is_when_no_host_given():
    settings = Settings(rabbitmq_url="amqp://custom:pass@myhost:5672/")
    assert settings.rabbitmq_url == "amqp://custom:pass@myhost:5672/"


def test_rabbitmq_host_overrides_url_with_composed_value():
    settings = Settings(
        rabbitmq_url="amqp://guest:guest@localhost:5672/",  # ignored once host is set
        rabbitmq_host="rabbitmq.regdesk.svc.cluster.local",
        rabbitmq_user="ingest-worker",
        rabbitmq_password="s3cret",
        rabbitmq_port=5672,
    )
    assert settings.rabbitmq_url == "amqp://ingest-worker:s3cret@rabbitmq.regdesk.svc.cluster.local:5672/"


def test_rabbitmq_host_without_credentials_falls_back_to_guest_guest():
    settings = Settings(rabbitmq_host="rabbitmq")
    assert settings.rabbitmq_url == "amqp://guest:guest@rabbitmq:5672/"
