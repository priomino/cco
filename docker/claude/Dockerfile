# syntax=docker/dockerfile:1
# Claude Code Offline - Claude Code CLI container (official native installer; tracks the latest release by default).
FROM ubuntu:24.04

# CLAUDE_VERSION: "latest" (default) or a version accepted by the official installer (verify the syntax before pinning)
ARG CLAUDE_VERSION=latest

LABEL com.claude-code-offline.project="cco" \
      com.claude-code-offline.component="claude" \
      com.claude-code-offline.requested-claude-version="${CLAUDE_VERSION}"

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git python3 less \
 && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a user "ubuntu" with uid 1000; replace it with our own non-root user.
RUN userdel -r ubuntu 2>/dev/null || true \
 && useradd --create-home --uid 1000 --shell /bin/bash cco \
 && mkdir -p /workspace /home/cco/.claude-cfg \
 && chown -R cco:cco /home/cco /workspace

COPY --chmod=0755 entrypoint.sh /usr/local/bin/cco-claude-entry

USER cco
WORKDIR /workspace
ENV PATH=/home/cco/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN curl -fsSL --retry 3 https://claude.ai/install.sh -o /tmp/claude-install.sh \
 && if [ "${CLAUDE_VERSION}" = "latest" ]; then bash /tmp/claude-install.sh; else bash /tmp/claude-install.sh "${CLAUDE_VERSION}"; fi \
 && rm -f /tmp/claude-install.sh

# Record what was installed (non-fatal); read by build-claude.ps1.
RUN { echo "built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo "requested_claude=${CLAUDE_VERSION}"; echo "claude=$(claude --version 2>&1)"; } > /home/cco/.cco-versions || true

CMD ["bash"]