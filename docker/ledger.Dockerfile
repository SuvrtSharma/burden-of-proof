# The reference ledger API and the load generator (ADR-0021).
# Base pinned by digest: Python 3.14.10, SQLite 3.46.1 (checked 2026-11-07).
FROM python:3.14-slim@sha256:af8a5aa14780025dbfbcfbc81bd8a91ebd87711dd5b0f48ed71090949dd7cb1d

WORKDIR /app
COPY reference/ reference/
COPY bench/__init__.py bench/loadgen.py bench/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --create-home app && mkdir /data && chown app /data
USER app
EXPOSE 8080
CMD ["python", "-m", "reference.ledger.server", "--db", "/data/ledger.db", "--host", "0.0.0.0", "--port", "8080"]
