# pais-research: pais-base plus tools for research data and for looking into a Workspace.
#
#   - UoA research drives from a Workspace, through the researcher's own UoA VPN session:
#     openconnect (FortiGate) + ocproxy (user-space forwarder, no tun device or root needed),
#     the `uoa-drive` wrapper, a current rclone (SMB backend) and Python's smbprotocol.
#     Only for approved use: see README → pais-research.
#   - Files and network: acl (getfacl/setfacl), bind9-dnsutils (dig, nslookup), smbclient,
#     krb5-user (kinit), proxychains4, sqlite3.
#   - Run:ai CLI: a `runai` helper that runs the copy in the person's home (~/.runai/bin/runai)
#     and explains how to install it when there is none. The CLI itself is NVIDIA's and is not
#     redistributed in this public image.
#
# Not here: fio (not packaged for Ubuntu 26.04).
FROM ghcr.io/drai-inn/pais-images/pais-base@sha256:3babe3a0d32cbe8c0afebf99d0d97d3ed9d433af945b95e90554e74ecbe8b826

# pais-base ends as USER nobody with BASH_ENV set; build as root, and keep env.sh out of RUN steps.
USER root
SHELL ["/usr/bin/env", "-u", "BASH_ENV", "/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      acl \
      bind9-dnsutils \
      krb5-user \
      ocproxy \
      openconnect \
      proxychains4 \
      smbclient \
      sqlite3 \
 && rm -rf /var/lib/apt/lists/* \
 && getfacl --version \
 && dig -v \
 && openconnect --version | head -1 \
 && openconnect --help | grep -q -- '--protocol=fortinet' \
 && command -v ocproxy \
 && smbclient --version \
 && sqlite3 --version

# --- rclone -----------------------------------------------------------------------------------------
# Ubuntu's rclone is 1.60, the first release with the SMB backend. The upstream release goes in
# /usr/local/bin, ahead of /usr/bin on PATH, checked against downloads.rclone.org's SHA256SUMS.
ARG RCLONE_VERSION=1.76.0
ARG RCLONE_SHA256=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7
RUN curl -fsSL -o /tmp/rclone.zip \
      "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" \
 && echo "${RCLONE_SHA256}  /tmp/rclone.zip" | sha256sum -c - \
 && unzip -q -j /tmp/rclone.zip "rclone-v${RCLONE_VERSION}-linux-amd64/rclone" -d /usr/local/bin \
 && chmod 0755 /usr/local/bin/rclone \
 && rm -f /tmp/rclone.zip \
 && /usr/local/bin/rclone completion bash /usr/share/bash-completion/completions/rclone \
 && /usr/local/bin/rclone version | head -1 | grep -q "v${RCLONE_VERSION}"

# --- smbprotocol --------------------------------------------------------------------------------------
# Into the default Python (uv-managed, marked externally managed, hence the override), so scripts can
# read files on a research drive directly: `import smbclient`.
ARG SMBPROTOCOL_VERSION=1.17.0
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv pip install --system --break-system-packages --no-cache --python /usr/local/bin/python \
      "smbprotocol==${SMBPROTOCOL_VERSION}" \
 && /usr/local/bin/python -c 'import smbclient'

# --- Wrappers -----------------------------------------------------------------------------------------
# uoa-drive: the UoA VPN session + forwards to the research-drive servers, and the rclone remotes.
# runai: runs ~/.runai/bin/runai, or says how to install it. PAIS_RUNAI_URL = the control plane it
# points a new install at (dev here; override in the Workspace template for another environment).
COPY --chmod=0755 uoa-drive runai /usr/local/bin/
ENV PAIS_RUNAI_URL=https://auckland.runai.dev.pais.auckland.ac.nz
RUN bash -n /usr/local/bin/uoa-drive && bash -n /usr/local/bin/runai

# As pais-base ends.
ENV BASH_ENV=/etc/pais/env.sh
USER nobody
