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

# Bake FastEmbed's BM25 term-weighting model into the image at build time
# rather than fetching it from HuggingFace on first use at runtime: this
# container's egress NetworkPolicy only allows RabbitMQ/Qdrant/Ollama (see
# deploy/charts/regdesk/templates/ingest-worker/networkpolicy.yaml), and even
# without that, KEDA scales this Deployment to zero between ingest runs, so
# "cached after first call" would otherwise mean a fresh download from the
# public internet on every single scale-up.
#
# Must pass cache_dir explicitly, matching app/config.py's
# fastembed_cache_dir default -- FastEmbed ignores HF_HOME and otherwise
# defaults to tempfile.gettempdir(), i.e. /tmp, which is a fresh emptyDir
# at runtime (see deploy/charts/regdesk/templates/_helpers.tpl's
# regdesk.tmpVolume) that would shadow whatever got baked in here.
RUN python -c "from fastembed import SparseTextEmbedding; SparseTextEmbedding(model_name='Qdrant/bm25', cache_dir='/opt/hf-cache')" && \
    chmod -R a+rX /opt/hf-cache

COPY app/ ./app/

USER app

# No inbound port: this is a queue consumer, not an HTTP service.
CMD ["python", "-m", "app.worker"]
