"""Async RabbitMQ consumer wrapper around aio-pika.

KEDA scales this worker on the queue named here (settings.queue_name), so
the queue must stay durable and the declared name must match the
ScaledObject's trigger metadata in deploy/charts/regdesk.
"""
from collections.abc import Awaitable, Callable

import aio_pika
from aio_pika.abc import AbstractIncomingMessage

from app.config import settings


class IngestQueueConsumer:
    def __init__(self) -> None:
        self._connection: aio_pika.abc.AbstractRobustConnection | None = None
        self._channel: aio_pika.abc.AbstractChannel | None = None

    async def connect(self) -> None:
        self._connection = await aio_pika.connect_robust(settings.rabbitmq_url)
        self._channel = await self._connection.channel()
        await self._channel.set_qos(prefetch_count=settings.prefetch_count)

    async def close(self) -> None:
        if self._connection is not None:
            await self._connection.close()

    async def consume(self, handler: Callable[[str], Awaitable[None]]) -> None:
        """Register `handler(doc_id)` for every message on the ingest queue.

        Each message is acked only after the handler returns successfully.
        On an exception it's requeued -- safe to retry because ingestion is
        idempotent (see app.idempotency).
        """
        queue = await self._channel.declare_queue(settings.queue_name, durable=True)

        async def _on_message(message: AbstractIncomingMessage) -> None:
            async with message.process(requeue=True, ignore_processed=True):
                doc_id = message.body.decode("utf-8").strip()
                await handler(doc_id)

        await queue.consume(_on_message)
