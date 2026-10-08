# --- builder: resolve and build wheels in an isolated layer ---
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# --- runtime: slim image, non-root, no build toolchain ---
FROM python:3.12-slim AS runtime

RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && \
    rm -rf /wheels requirements.txt

COPY app/ ./app/

USER app
EXPOSE 8000

# Streamable-HTTP MCP server; /healthz is the liveness probe target.
CMD ["python", "-m", "app.server"]
