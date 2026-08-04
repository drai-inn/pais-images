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
