# --- builder: resolve and build wheels in an isolated layer ---
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
# --timeout/--retries: this step downloads from PyPI, which is the one
# part of the build that depends on an external network rather than a
# local cache -- generous values absorb transient slow/flaky connections
# instead of failing the whole build on a single read timeout.
RUN pip wheel --no-cache-dir --timeout 100 --retries 5 --wheel-dir /wheels -r requirements.txt

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
EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
