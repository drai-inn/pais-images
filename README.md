# pais-images

Container images for PAIS Coder workspaces, built by CI and published to GitHub Packages (GHCR).

## Images

| Image | Tag | Purpose |
| --- | --- | --- |
| `ghcr.io/drai-inn/pais-images/python-base` | `latest`, `sha-<git>`, `python-base-v*` | General Python research / data-science workbench base. Ships conda (miniforge) + uv only; researchers build their own environments. Used by the `python-base` Coder template. |
| `ghcr.io/drai-inn/pais-images/pais-base` | `pais-base-v<n>` (from `VERSION`), `sha-<git>` | `python-base` plus `nss_wrapper`, for Workspaces running as the person's FreeIPA uid. See below. |
| `ghcr.io/drai-inn/pais-images/pais-research` | `pais-research-v<n>` (from `VERSION`), `sha-<git>` | `pais-base` plus UoA research-drive access (the researcher's own UoA VPN session, `uoa-drive`, rclone) and admin tools (ACLs, DNS, SMB, Kerberos, sqlite). See below. |
| `ghcr.io/drai-inn/pais-images/pais-research-gpu` | `pais-research-gpu-v<n>` (from `VERSION`), `sha-<git>` | `pais-research` plus PyTorch and the common ML/data stack in the default Python, with a JupyterLab kernel. See below. |
| `ghcr.io/drai-inn/pais-images/runai-mcp-server` | `<Run:ai version>` (e.g. `3.0.20`), `sha-<git>`, `runai-mcp-server-v*` | NVIDIA Run:ai's MCP server, built from the open-source `dsx-ai-factory/run-ai` at the release tag in `images/runai-mcp-server/VERSION`. Runs on ai-gpu-test behind agentgateway (the MCP hub). |
| `ghcr.io/drai-inn/pais-images/nfs-server` | `<nfs-utils version>` (e.g. `2.6.4-3ubuntu5.1`), `sha-<git>`, `nfs-server-v*` | Runs the node kernel's NFS server from a privileged pod: Ubuntu's `nfs-kernel-server` at the version in `images/nfs-server/VERSION`. Serves workspace homes on ai-gpu-test. |

Renamed from `datasci-cpu` on 2026-09-14: the old name claimed CPU-only while the template offers a
GPU and the driver is injected at runtime regardless of what is baked. GHCR packages cannot be
renamed, so `datasci-cpu` remains published for anything still pulling it.

## Build & publish

CI (`.github/workflows/build.yml`) builds on push to `main` (when the image or workflow changes)
and on `python-base-v*` tags, pushing to GHCR. Packages are **public**, so the cluster pulls with
no image pull secret.

To rebuild manually: run the `build` workflow via *Actions → build → Run workflow*.

## python-base

`FROM codercom/enterprise-base:ubuntu` (the base `pais-cpu` uses), plus:

- **miniforge** (conda) at `/opt/conda`. New envs land in `~/.conda/envs`, on the workspace home
  PVC, so they persist across restarts. Only `conda` and `mamba` are on PATH (`/opt/conda/condabin`);
  the base env's `python`/`pip` are not.
- **uv** at `/usr/local/bin`. Cache defaults to `~/.cache/uv` on the home PVC.
- **Default Python**: a uv-managed CPython (minor pinned by `PYTHON_VERSION`) as `python`/`python3`
  in `/usr/local/bin`, ahead of Ubuntu's `/usr/bin/python3`.
- **CLI tools**: `tmux` (so long jobs survive a web-terminal reload), `git-lfs`, `gfortran` +
  `pkg-config` + `cmake` (source builds of scientific packages), `ncdu` (find what is filling the
  home PVC), `pandoc` (nbconvert to non-HTML formats; no LaTeX, so no PDF), `ripgrep`, `fd`,
  `tree`, `zip`.
- **Shell defaults** in `/etc/bash.bashrc`, not `~/.bashrc`, because the home PVC masks the
  latter: the bash-completion loader (plus `uv`/`uvx` completions) and
  `alias ls='ls --color=auto'`.
- **Timezone** `Pacific/Auckland` (`TZ` plus `/etc/localtime`); the base image is UTC.

Not included by design: ML/data-science libraries and a CUDA toolkit — researchers build their own
env with conda/uv. The driver and `nvidia-smi` are injected by the container runtime when the
workspace requests a GPU, so no separate GPU image is needed.

## pais-base

The PAIS Workspace image: a standalone Python + R research workbench on `ubuntu:26.04` (pinned by digest), for
Workspaces that run as the person's FreeIPA uid. Used by the `ubuntu-shell` Run:ai templates in
`drai-inn/ai-gpu-deployment` (`services/ai-gpu-test/identity/ws-shell/runai-templates/`).

- **Python:** miniforge (conda) at `/opt/conda`, envs in `~/.conda/envs`; uv, with a uv-managed CPython as the default
  `python`; Node.js 24.
- **GPU monitoring:** `nvtop`, `nvitop`.
- **Browser tools:** JupyterLab, code-server, ttyd and File Browser Quantum. Nothing starts by itself: the template's
  start-up runs the ones it exposes.
- **Coding agents:** opencode and pi (with the PAIS provider), Claude Code.
- **Remote access:** `openssh-server` and `openssh-sftp-server` (for `sshd -i` as the person; no host keys in the
  image), `websocat`, `gh`.
- **Names:** `libnss-wrapper`. The uid has no entry in `/etc/passwd`; the start-up writes passwd and group copies in
  `/tmp` and the template preloads the library.
- **Per-Workspace settings:** `/etc/pais/env.sh` sets thread caps from the cgroup CPU limit, `~/.local/bin` first on
  `PATH`, `USER`/`LOGNAME`, a per-Workspace `OPENCODE_DB` and an unlimited stack. It is sourced by interactive bash
  (`/etc/bash.bashrc`), non-interactive bash (`BASH_ENV`) and the start-up.
- **Locale:** `en_NZ.UTF-8`, timezone `Pacific/Auckland`.
- **Pinning:** release downloads by version and SHA-256 (ARGs in the Dockerfile), images by digest. Apt packages are
  not pinned.
- **Tags:** the contents of `images/pais-base/VERSION` (e.g. `pais-base-v1`) and `sha-<git>`. No `latest`: the template
  pins a digest.
- **New version:** change `images/pais-base/` and bump `VERSION` in the same commit, or the build overwrites the
  current version tag. Then move the digest in the template.

## pais-research

`pais-base` (at a pinned digest) plus:

- **UoA research drives**, through the researcher's **own** UoA VPN session started inside their Workspace:
  `openconnect` (FortiGate) and `ocproxy` (a user-space forwarder: no tun device, no root, no change to the pod or
  the cluster), wrapped by **`uoa-drive`**:
  ```
  uoa-drive setup        # once: rclone remotes uoa-rd (research.drive) and uoa-files (files/research) with your UoA login
  uoa-drive up           # UoA password, then MFA code; then runs in the background
  rclone lsf uoa-rd:<drive>
  rclone copy uoa-rd:<drive>/data /workspaces/$RUNAI_PROJECT/data -P
  uoa-drive down
  ```
  Only the two drive servers' SMB port is forwarded, to localhost in that Workspace; `uoa-drive up --socks` also
  opens a SOCKS5 proxy on `localhost:1080` (ssh, rsync, curl to campus). Copy access, not a mount. **Use needs
  approval** from UoA ITS and CeR (proposal: research drives from PAIS workspaces); until then, platform team only.
- **rclone** current release (`RCLONE_VERSION`, checksum-pinned) in `/usr/local/bin`, ahead of Ubuntu's 1.60; Python
  **smbprotocol** in the default Python (`import smbclient`).
- **Tools:** `acl` (getfacl/setfacl), `bind9-dnsutils` (dig, nslookup), `smbclient`, `krb5-user` (kinit),
  `proxychains4`, `sqlite3`. Not `fio` (not packaged for Ubuntu 26.04).
- **`runai`**: a helper that runs the person's own CLI in `~/.runai/bin/runai` (their home follows them into every
  Workspace) and, on first use, points it at `$PAIS_RUNAI_URL` and starts `runai login remote-browser`. With no CLI
  installed it says how to install it from the Run:ai UI. NVIDIA's CLI is not redistributed in this public image.
  `PAIS_RUNAI_URL` defaults to the dev control plane; set it in the Workspace template for another environment.

- **Tags:** `images/pais-research/VERSION` (e.g. `pais-research-v1`) and `sha-<git>`. **New version:** change the folder
  and bump `VERSION` in the same commit.

## pais-research-gpu

`pais-research` plus the common GPU/ML Python stack (`requirements.txt`: torch, torchvision, torchaudio, numpy, scipy,
pandas, scikit-learn, matplotlib, transformers, accelerate, datasets, safetensors, tensorboard), installed in the
**default Python** so `python -c 'import torch'` works with nothing to install, plus a JupyterLab kernel
**Python 3 (GPU: PyTorch)**. A researcher's own environment builds on it without downloading torch again:
`uv venv --system-site-packages .venv`. torch from PyPI bundles its CUDA runtime; the driver comes from the GPU node.
Several GB larger than `pais-research`.

- **Tags:** `images/pais-research-gpu/VERSION` and `sha-<git>`. Built FROM the `pais-research` version in
  `images/pais-research/VERSION` (CI passes it as `BASE`), so to move onto a new `pais-research`, bump this `VERSION`
  too. CI frees runner disk first and uses no layer cache for it (it would fill the repository's Actions cache).

## runai-mcp-server

NVIDIA Run:ai's MCP server (`runai-mcp-server serve`): MCP tools over Run:ai's REST API, acting as the caller's own
Run:ai token in HTTP mode. NVIDIA publishes no image of the open-source server (NGC's
`nvcr.io/nvidia/runai/runai-mcp-server` is the commercial 2.x line, with a different tool set), so this builds it.

- **Source:** `https://github.com/dsx-ai-factory/run-ai`, directory `runai-mcp-server/`, at the tag in
  `images/runai-mcp-server/VERSION`. Keep it equal to the Run:ai control plane's version it serves.
- **Build:** clones only `runai-mcp-server/` and the in-repo modules its `go.mod` `replace`s point to, builds with the
  module's own `go.sum`, `linux/amd64`. The final stage is upstream's Dockerfile (scratch, CA certificates, user
  65532).
- **Tags:** the version (e.g. `3.0.20`) and `sha-<git>`. No `latest`: deployments pin a version by digest.
- **New version:** change `VERSION` and push to `main`.
- **Deployed by:** `drai-inn/ai-gpu-deployment`, `clusters/ai-gpu-test/runai-mcp/`.

## nfs-server

Configures and runs the **node kernel's** NFS server (`nfsd`) from a container. The image holds only the user-space
side: `rpc.nfsd`, `rpc.mountd`, `exportfs` and `nfsdcld`, plus `rpcbind` and `rpc.statd` for NFSv3. So the pod must be
privileged, and the node must have the `nfsd` module (Ubuntu 24.04 nodes do).

- **Why our own:** the public kernel-NFS images are unmaintained (`itsthenetwork/nfs-server-alpine` last tagged
  2019, `erichough/nfs-server` 2020).
- **Contents:** `ubuntu:noble-<date>` and Ubuntu's `nfs-kernel-server` / `nfs-common`, pinned to the version in
  `images/nfs-server/VERSION`. When Ubuntu publishes a new version, the build fails until `VERSION` follows it.
- **Run:** `nfs-server run` serves the exports in `/etc/exports.d/*.exports` (`exports(5)`), and stops the server
  (`exportfs -ua`, `rpc.nfsd 0`) on TERM. `nfs-server check` is the probe.
- **Settings:** environment variables, listed at the top of `entrypoint.sh`. `NFS_VERSIONS` defaults to `4.1 4.2`;
  NFSv3 (`3`) also starts `rpcbind` and `rpc.statd`, on fixed ports.
- **Tags:** the version and `sha-<git>`. No `latest`: deployments pin a version by digest.
- **New version:** change `VERSION` and push to `main`.
- **Deployed by:** `drai-inn/ai-gpu-deployment`, `clusters/ai-gpu-test/workspaces-home/`.
