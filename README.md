# pais-images

Container images for PAIS Coder workspaces, built by CI and published to GitHub Packages (GHCR).

## Images

| Image | Tag | Purpose |
| --- | --- | --- |
| `ghcr.io/drai-inn/pais-images/python-base` | `latest`, `sha-<git>`, `python-base-v*` | General Python research / data-science workbench base. Ships conda (miniforge) + uv only; researchers build their own environments. Used by the `python-base` Coder template. |

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
