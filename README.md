# pais-images

Container images for PAIS Coder workspaces, built by CI and published to GitHub Packages (GHCR).

## Images

| Image | Tag | Purpose |
| --- | --- | --- |
| `ghcr.io/drai-inn/pais-images/python-base` | `latest`, `sha-<git>`, `python-base-v*` | General Python research / data-science workbench base. Ships conda (miniforge) + uv only; researchers build their own environments. Used by the `python-base` Coder template. |
| `ghcr.io/drai-inn/pais-images/runai-mcp-server` | `<Run:ai version>` (e.g. `3.0.20`), `sha-<git>`, `runai-mcp-server-v*` | NVIDIA Run:ai's MCP server, built from the open-source `dsx-ai-factory/run-ai` at the release tag in `images/runai-mcp-server/VERSION`. Runs on ai-gpu-test behind agentgateway (the MCP hub). |

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
