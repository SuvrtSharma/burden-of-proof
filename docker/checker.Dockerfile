# The whole tooling on Linux: Lean toolchain (pinned by lean-toolchain),
# leancheck, the ledger spec and model, and the Python test suite (ADR-0021).
# Same base as the ledger image, so conformance runs on the same SQLite build
# that the benchmark measures.
FROM python:3.14-slim@sha256:af8a5aa14780025dbfbcfbc81bd8a91ebd87711dd5b0f48ed71090949dd7cb1d

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home app
USER app
WORKDIR /home/app/repo
ENV PATH=/home/app/.elan/bin:$PATH PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# elan from its official installer; the toolchain itself comes from lean-toolchain.
COPY --chown=app lean-toolchain ./
RUN curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o /tmp/elan-init.sh \
    && sh /tmp/elan-init.sh -y --default-toolchain "$(cat lean-toolchain)" && rm /tmp/elan-init.sh \
    && lean --version

COPY --chown=app . .
RUN python -m venv /home/app/venv && /home/app/venv/bin/pip install -q -e ".[dev]"
ENV PATH=/home/app/venv/bin:$PATH
RUN (cd tools/leancheck && lake build) && lake build

CMD ["python", "-m", "pytest", "-q", "-rs"]
