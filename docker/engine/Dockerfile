# syntax=docker/dockerfile:1
# Claude Code Offline - engine image (Unsloth, GGUF-only). Built by scripts/windows/build-engine.ps1
FROM ubuntu:24.04

# UNSLOTH_VERSION: "latest" (default) or an exact release such as 2026.9.14
ARG UNSLOTH_VERSION=latest
# Optional SHA-256 of install.sh; empty = do not verify
ARG UNSLOTH_INSTALLER_SHA256=
ARG ENGINE_PYTHON=3.12
ARG LLAMA_BACKEND=cpu

LABEL com.claude-code-offline.project="cco" \
      com.claude-code-offline.component="engine" \
      com.claude-code-offline.requested-unsloth-version="${UNSLOTH_VERSION}" \
      com.claude-code-offline.llama-backend="${LLAMA_BACKEND}"

# libgomp1: OpenMP runtime needed by the prebuilt llama.cpp binaries (llama-server, llama-quantize)
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a user "ubuntu" with uid 1000; replace it with our own non-root user.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd --create-home --uid 1000 --shell /bin/bash cco \
 && mkdir -p /home/cco/.cache/huggingface \
 && chown -R cco:cco /home/cco

USER cco
WORKDIR /home/cco
ENV HF_HOME=/home/cco/.cache/huggingface

# Constraints file: empty when tracking latest, "unsloth==X" when a version is requested.
# (verify: uv and pip both honour these variables; only matters when pinning)
RUN if [ "${UNSLOTH_VERSION}" != "latest" ]; then printf 'unsloth==%s\n' "${UNSLOTH_VERSION}" > /home/cco/constraints.txt; else : > /home/cco/constraints.txt; fi
ENV UV_CONSTRAINT=/home/cco/constraints.txt \
    PIP_CONSTRAINT=/home/cco/constraints.txt

RUN curl -fsSL --retry 3 https://unsloth.ai/install.sh -o /tmp/install.sh \
 && if [ -n "${UNSLOTH_INSTALLER_SHA256}" ]; then echo "${UNSLOTH_INSTALLER_SHA256}  /tmp/install.sh" | sha256sum -c -; fi \
 && UNSLOTH_NO_TORCH=1 UNSLOTH_SKIP_AUTOSTART=1 \
    UNSLOTH_PYTHON="${ENGINE_PYTHON}" UNSLOTH_LLAMA_CPP_BACKEND="${LLAMA_BACKEND}" \
    sh /tmp/install.sh \
 && rm -f /tmp/install.sh

# Record what was installed (non-fatal); read by build-engine.ps1 and by step 07.
RUN { echo "built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "requested_unsloth=${UNSLOTH_VERSION}"; find /home/cco -maxdepth 9 -type d -name '*.dist-info' \( -name 'unsloth-*' -o -name 'unsloth_zoo-*' \) 2>/dev/null; } > /home/cco/.cco-versions || true

CMD ["bash"]