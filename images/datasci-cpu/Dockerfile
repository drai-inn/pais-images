# pais-datasci-cpu: general Python + R research workbench base image for Coder workspaces.
#
# Managers only, by design: conda (miniforge) + uv are baked so researchers build their own
# environments; no ML/data-science libraries are preinstalled. Editors (JupyterLab, code-server,
# VS Code Web) are added at workspace runtime by the Coder registry modules in the template.
#
# Built on codercom/enterprise-base:ubuntu (the same base pais-cpu uses): provides the UID-1000
# `coder` user, HOME=/home/coder, git/curl/pipx and passwordless sudo. The workspace mounts the
# persistent home PVC at /home/coder, so anything conda/uv writes under $HOME (envs, caches)
# survives workspace restarts with no extra configuration.
FROM codercom/enterprise-base:ubuntu

USER root

# --- timezone ---------------------------------------------------------------------------------
# The base image is UTC. Researchers are in NZ, so make wall-clock times in logs, notebook output
# and scheduled jobs local. TZ is exported (glibc and Python read it) and /etc/localtime is
# repointed for anything that reads the file directly.
ENV TZ=Pacific/Auckland
RUN ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
 && echo "${TZ}" > /etc/timezone

# --- system tools -----------------------------------------------------------------------------
# The base already ships build-essential, gcc/g++, git, curl, wget, jq, less, htop, rsync, unzip,
# vim and openssh-client. Added here, in rough order of why:
#   tmux            the Coder web terminal drops its session on reload, killing long conda solves,
#                   uv syncs and model fits; tmux lets researchers detach instead
#   bash-completion the completion loader itself (see the shell defaults section below)
#   git-lfs         datasets and model weights clone as pointer files without it
#   gfortran        conda-forge ships wheels, but `uv pip install` falls back to compiling from
#   pkg-config      source, and scientific packages need a Fortran compiler plus these to build
#   cmake
#   ncdu            the home PVC is quota-bound and conda envs / uv caches fill it; researchers
#                   need to see what is eating the volume
#   pandoc          nbconvert to anything but HTML requires it. No LaTeX: texlive is far too large
#                   for a base image, so PDF export is not covered
#   ripgrep         search and file-wrangling basics
#   fd-find         installs as `fdfind` on Debian/Ubuntu (name clash with fdclone), so it is
#                   symlinked to the `fd` everyone actually types
#   tree
#   zip
#
# zstd is deliberately absent: miniforge ships one at /opt/conda/bin/zstd, which precedes /usr/bin
# on PATH, so the apt package would never be the one that runs.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      bash-completion \
      cmake \
      fd-find \
      gfortran \
      git-lfs \
      ncdu \
      pandoc \
      pkg-config \
      ripgrep \
      tmux \
      tree \
      zip \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd

# --- interactive shell defaults ---------------------------------------------------------------
# Ubuntu puts the bash-completion hook and `alias ls --color=auto` in ~/.bashrc, which the image
# seeds from /etc/skel. The home PVC mounts over /home/coder and masks it, so in a workspace
# neither ever runs. Set them system-wide in /etc/bash.bashrc instead: interactive shells read it
# directly and login shells get it via /etc/profile.
RUN echo ". /usr/share/bash-completion/bash_completion" >> /etc/bash.bashrc \
 && echo "alias ls='ls --color=auto'" >> /etc/bash.bashrc

# --- miniforge (conda) at a system path -------------------------------------------------------
# Installed to /opt/conda, owned by root. Because the runtime user (coder, UID 1000) does not own
# /opt/conda, conda transparently creates new environments under ~/.conda/envs — i.e. on the home
# PVC, so they persist. The condarc below makes that explicit and points package/env dirs at $HOME.
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/bin:${PATH}
RUN curl -fsSL -o /tmp/miniforge.sh \
      "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh" \
 && bash /tmp/miniforge.sh -b -p "${CONDA_DIR}" \
 && rm -f /tmp/miniforge.sh \
 && "${CONDA_DIR}/bin/conda" clean -afy

# System condarc: keep envs and package cache on the home PVC so they persist across restarts,
# and make `conda activate` available in interactive bash for every user.
#
# Edited through `conda config --system`, never by writing the file directly. Miniforge ships its
# own /opt/conda/.condarc carrying `channels: [conda-forge]`, and overwriting it leaves conda with
# no channels at all, so every `conda create` fails with NoChannelsConfiguredError.
RUN conda config --system --prepend envs_dirs '~/.conda/envs' \
 && conda config --system --prepend pkgs_dirs '~/.conda/pkgs' \
 && conda config --system --show channels | grep -q conda-forge \
 && echo ". ${CONDA_DIR}/etc/profile.d/conda.sh" >> /etc/bash.bashrc

# --- uv ---------------------------------------------------------------------------------------
# Official static binaries copied from the upstream image. uv's cache defaults to ~/.cache/uv,
# which is on the home PVC, so downloaded wheels/interpreters persist across restarts.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# uv's own completions, written to the bash-completion lookup dir so the loader sources them on
# first use of `uv`/`uvx` rather than in every shell startup.
RUN uv generate-shell-completion bash > /usr/share/bash-completion/completions/uv \
 && uvx --generate-shell-completion bash > /usr/share/bash-completion/completions/uvx

# JupyterLab baked via uv as an isolated tool, on PATH as /usr/local/bin/jupyter-lab. The Coder
# jupyterlab registry module is not used: in path mode it hardcodes its healthcheck at the root
# /api while serving under a base_url prefix, so the app is always reported unhealthy. The
# template starts this baked JupyterLab itself with a matching healthcheck instead.
#
# The UV_* settings are scoped to this RUN deliberately. As ENV they persist past `USER coder` into
# the running workspace, where uid 1000 cannot write to root-owned /opt/uv, so any uv operation
# needing an interpreter download dies with
#   error: failed to create directory `/opt/uv/python`: Permission denied (os error 13)
# Unscoped, uv falls back to ~/.local/share/uv and ~/.local/bin, both on the home PVC.
RUN UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv tool install jupyterlab \
 && test -x /usr/local/bin/jupyter-lab

# uv's default tool bin dir at runtime. Deliberately not created here: the home PVC mounts over
# /home/coder and masks anything the image writes there, so the entry resolves only once uv makes
# it. A non-existent PATH entry is harmless meanwhile.
ENV PATH=/home/coder/.local/bin:${PATH}

USER coder
