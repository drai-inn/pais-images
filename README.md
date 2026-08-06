# pais-images

Container images for PAIS Coder workspaces, built by CI and published to GitHub Packages (GHCR).

## Images

| Image | Tag | Purpose |
| --- | --- | --- |
| `ghcr.io/drai-inn/pais-images/datasci-cpu` | `latest`, `sha-<git>`, `datasci-cpu-v*` | General Python research / data-science workbench base. Ships conda (miniforge) + uv only; researchers build their own environments. Used by the `pais-datasci-cpu` Coder template. |

## Build & publish

CI (`.github/workflows/build.yml`) builds on push to `main` (when the image or workflow changes)
and on `datasci-cpu-v*` tags, pushing to GHCR. Packages are **public**, so the cluster pulls with
no image pull secret.

To rebuild manually: run the `build` workflow via *Actions → build → Run workflow*.

## datasci-cpu

`FROM codercom/enterprise-base:ubuntu` (the base `pais-cpu` uses), plus:

- **miniforge** (conda) at `/opt/conda`. New envs land in `~/.conda/envs`, on the workspace home
  PVC, so they persist across restarts.
- **uv** at `/usr/local/bin`. Cache defaults to `~/.cache/uv` on the home PVC.
- **CLI tools**: `tmux` (so long jobs survive a web-terminal reload), `git-lfs`, `gfortran` +
  `pkg-config` + `cmake` (source builds of scientific packages), `ncdu` (find what is filling the
  home PVC), `pandoc` (nbconvert to non-HTML formats; no LaTeX, so no PDF), `ripgrep`, `fd`,
  `tree`, `zip`.
- **Shell defaults** in `/etc/bash.bashrc`, not `~/.bashrc`, because the home PVC masks the
  latter: the bash-completion loader (plus `uv`/`uvx` completions) and
  `alias ls='ls --color=auto'`.
- **Timezone** `Pacific/Auckland` (`TZ` plus `/etc/localtime`); the base image is UTC.

Not included by design: ML/data-science libraries (build your own env) and CUDA/GPU support (a
future `datasci-gpu` image).
