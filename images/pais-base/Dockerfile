# pais-base: the PAIS Workspace image, a general Python + R research workbench.
#
# Managers only, by design: conda (miniforge) + uv are baked so researchers build their own
# environments; no ML/data-science libraries are preinstalled. The browser tools (JupyterLab,
# code-server, ttyd, File Browser) and the coding agents are baked too; the workload's start-up
# decides which of them run.
#
# The Workspace runs as the owner's FreeIPA uid, which has no entry in this image's /etc/passwd. The
# start-up (ai-gpu-deployment, services/ai-gpu-test/identity/ws-shell/runai-templates/ws-init.sh)
# writes passwd and group copies in /tmp and the template preloads libnss_wrapper to read them. The
# owner's home is mounted from outside with HOME set to it, so anything conda/uv writes under $HOME
# (envs, caches) persists. Nothing here may assume the home's path: refer to it as ~ or $HOME.
#
# Everything fetched is pinned: the base by digest, release downloads by version and SHA-256. Apt
# packages are not, so a rebuild still moves them. To move a tool, bump its ARGs and VERSION together.
FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The image's own uid-1000 user. Workspaces never run as it, and the uid belongs to nobody here.
RUN userdel -r ubuntu

# --- timezone and locale ----------------------------------------------------------------------
# Researchers are in NZ, so wall-clock times in logs, notebook output and scheduled jobs are local,
# and dates and numbers format the NZ way. TZ is exported (glibc and Python read it) and
# /etc/localtime is repointed for anything that reads the file directly. LC_ALL stays unset so a
# researcher can still override a single LC_* category.
ENV TZ=Pacific/Auckland \
    LANG=en_NZ.UTF-8 \
    LANGUAGE=en_NZ:en

# --- system packages --------------------------------------------------------------------------
# This is the interactive environment researchers land in and there is NO sudo (restricted PSA
# drops ALL capabilities and sets no_new_privs), so anything absent here cannot be added by the
# user later. The set was reconciled against NeSI's OOD base image
# (nesi/nesi-ood-base ansible/roles/nesi.compute/defaults/main.yml) on 2026-09-26, keeping what
# suits a container workbench and dropping what only makes sense on a bare-metal HPC node.
#
# Basics:
#   build-essential gcc, g++, make, libc headers
#   ca-certificates curl wget git openssh-client less jq unzip rsync iproute2 htop vim
#   locales tzdata  see above
#   python3 python3-pip pipx
#                   Ubuntu's python, for apt-installed tools and pipx. The default `python` is uv's
#                   (below)
#   libnss-wrapper  names for the Workspace's uid; see the header
#
# Remote access (installed, started only by a template that wants them):
#   openssh-server  `sshd -i` as the person, one per connection; nothing listens by default
#   openssh-sftp-server
#                   sftp, and scp (which speaks SFTP since OpenSSH 9), for sshd and for Tailscale SSH
#
# Session and shell:
#   tmux            a browser terminal drops its session on reload, killing long conda solves,
#   screen          uv syncs and model fits; these let researchers detach instead
#   bash-completion the completion loader itself (see the shell defaults section below)
#   zsh fish        the login shell stays /bin/bash: it is fixed in the start-up's passwd entry
#   tcsh ksh        and there is no chsh without root. These are for `exec zsh` and for scripts
#                   with a non-bash shebang, NOT a way to change your default shell.
#
# Editors:
#   nano            vim owns the `editor` alternative otherwise, so an unset EDITOR drops
#                   researchers into vim at their first `git commit`
#
# Debugging and profiling:
#   gdb             ptrace WORKS here despite the dropped capabilities: dropping ALL does not
#   strace          remove ptrace against your own descendants, and ptrace_scope is 1, which
#   ltrace          permits exactly the launch-then-attach pattern these use. Verified in a live
#                   workspace 2026-09-26 (PTRACE_TRACEME and PTRACE_ATTACH to a child both OK).
#
#                   `perf` is DELIBERATELY ABSENT and must not be added back: perf_event_open
#                   fails EPERM under the RuntimeDefault seccomp profile and perf_event_paranoid
#                   is 4, so linux-tools would ship ~20 MB that can only print a permissions
#                   error. NeSI carry perf because they are on bare metal; we cannot.
#   lsof            what is holding that file / port
#   psmisc          pstree, killall, fuser
#
# Monitoring (the cgroup limit is the only thing standing between a researcher and an OOM kill, so
# this is not idle curiosity):
#   nvtop           the GPU equivalent of htop (nvitop, a uv tool below, is the other common one)
#   btop            nicer htop, and the one most people now expect
#   sysstat         iostat/pidstat/mpstat. Homes and projects are NFS, so "is it me or is it the
#                   filesystem" is otherwise unanswerable from inside the pod
#   numactl         multi-socket GPU nodes; pinning matters for memory-bound work
#   hwloc           lstopo. NB it reports the NODE topology, not the cgroup's slice of it
#   pciutils        lspci, to see which GPU was actually injected
#   time            /usr/bin/time -v gives peak RSS, which is how you pick a memory size. Bash's
#                   `time` builtin shadows it: use `\time -v` or the path
#
# Building from source (conda-forge ships wheels, but `uv pip install` falls back to compiling
# and scientific packages still expect a full autotools chain):
#   gfortran        a Fortran compiler plus these are the usual hard requirements
#   pkg-config
#   cmake
#   autoconf automake m4
#   libtool         plus libtool-bin: the `libtool` package ships libtoolize and the m4 macros but
#   libtool-bin     NOT /usr/bin/libtool, which is the one a person types
#   bison flex      parser generators, pulled in by more build systems than you would expect
#   swig            C/C++ bindings
#   patchelf        repairing RPATHs in prebuilt wheels
#   universal-ctags provides `ctags`
#
# Data movement and transfer:
#   git-lfs         datasets and model weights clone as pointer files without it
#   rclone          the general answer for moving research data to and from object storage
#   aria2 lftp      resumable and parallel fetches of large datasets over http/ftp
#   netcat-openbsd  provides `nc`, for checking whether a port is actually reachable
#
# Storage and compression:
#   ncdu            homes are quota-bound and conda envs / uv caches fill them; researchers need to
#                   see what is eating the space
#   pigz            parallel gzip; tar.gz is still the default
#   p7zip-full      provides `7z`, for archives that turn up from collaborators
#   zip
#   zstd
#
# Documents, plotting and text:
#   pandoc          nbconvert to anything but HTML requires it. No LaTeX: texlive is far too large
#                   for a base image, so PDF export is not covered
#   graphviz        provides `dot`, which pydot, sklearn tree plots and torchviz all shell out to
#   imagemagick     quick image conversion and inspection without writing Python
#   datamash        quick summary statistics over a column without writing Python
#   dos2unix        files arrive from Windows collaborators
#   bc              arithmetic in shell scripts
#
#                   gnuplot is DELIBERATELY ABSENT: 164 packages and ~100 MB, because it drags in
#                   the X11 and font stack. Anyone plotting here has matplotlib.
#
# Search and file wrangling:
#   ripgrep         search and file-wrangling basics
#   fd-find         installs as `fdfind` on Debian/Ubuntu (name clash with fdclone), so it is
#                   symlinked to the `fd` everyone actually types
#   file            identify what a file actually is
#   parallel        GNU parallel, for embarrassingly parallel work without writing a job script
#   tree
#
# Man pages are not shipped: the Ubuntu container image excludes /usr/share/man.
#
# Ubuntu's nvtop carries the file capability cap_perfmon=ep, and a binary with file capabilities
# cannot be exec'd in a pod that drops ALL capabilities ("Operation not permitted"). nvtop reads the
# GPU through NVML and needs no capability, so it is stripped.
#
# openssh-server generates host keys at install. They are removed: an image layer is the same for
# every Workspace, and an sshd run as the person brings its own key.
RUN apt-get update \
 && apt-get upgrade --yes \
 && apt-get install --yes --no-install-recommends \
      aria2 \
      autoconf \
      automake \
      bash-completion \
      bc \
      bison \
      btop \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      datamash \
      dos2unix \
      fd-find \
      file \
      fish \
      flex \
      gdb \
      gfortran \
      git \
      git-lfs \
      graphviz \
      htop \
      hwloc \
      imagemagick \
      iproute2 \
      jq \
      ksh \
      less \
      lftp \
      libnss-wrapper \
      libtool \
      libtool-bin \
      locales \
      lsof \
      ltrace \
      m4 \
      nano \
      ncdu \
      netcat-openbsd \
      numactl \
      nvtop \
      openssh-client \
      openssh-server \
      openssh-sftp-server \
      p7zip-full \
      pandoc \
      parallel \
      patchelf \
      pciutils \
      pigz \
      pipx \
      pkg-config \
      psmisc \
      python3 \
      python3-pip \
      rclone \
      ripgrep \
      rsync \
      screen \
      strace \
      swig \
      sysstat \
      tcsh \
      time \
      tmux \
      tree \
      tzdata \
      universal-ctags \
      unzip \
      vim \
      wget \
      zip \
      zsh \
      zstd \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
 && rm -f /etc/ssh/ssh_host_* \
 && setcap -r /usr/bin/nvtop \
 && ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
 && echo "${TZ}" > /etc/timezone \
 && locale-gen en_NZ.UTF-8 \
 && locale -a | grep -qx 'en_NZ.utf8'

# Fail the build if nss_wrapper isn't where the template's LD_PRELOAD points, or doesn't resolve a
# name on this image's glibc.
RUN set -eu; \
    lib=/usr/lib/x86_64-linux-gnu/libnss_wrapper.so; \
    d=$(mktemp -d); \
    cp /etc/passwd /etc/group "$d"; \
    echo 'probe:x:14000:20001:probe:/tmp:/bin/bash' >> "$d/passwd"; \
    test "$(LD_PRELOAD=$lib NSS_WRAPPER_PASSWD=$d/passwd NSS_WRAPPER_GROUP=$d/group getent passwd 14000 | cut -d: -f1)" = probe; \
    rm -rf "$d"

# --- interactive shell defaults and per-Workspace settings ------------------------------------
# Ubuntu puts the bash-completion hook and `alias ls --color=auto` in ~/.bashrc, which a
# researcher's home may lack. Set them system-wide in /etc/bash.bashrc instead: interactive shells
# read it directly and login shells get it via /etc/profile.
#
# /etc/pais/env.sh holds what depends on the Workspace (its CPU limit, its name, the home's path).
# It is sourced by every way into a Workspace: interactive shells through /etc/bash.bashrc,
# non-interactive bash (`ws-shell <name> -- cmd`) through BASH_ENV, and the start-up sources it
# itself so the tools it starts inherit it.
COPY env.sh /etc/pais/env.sh
RUN echo ". /usr/share/bash-completion/bash_completion" >> /etc/bash.bashrc \
 && echo "alias ls='ls --color=auto'" >> /etc/bash.bashrc \
 && echo ". /etc/pais/env.sh" >> /etc/bash.bashrc

# --- miniforge (conda) at a system path -------------------------------------------------------
# Installed to /opt/conda, owned by root. Because the runtime user (the owner's uid) does not own
# /opt/conda, conda creates new environments under ~/.conda/envs, in the home, so they persist.
# The condarc below makes that explicit and points package/env dirs at $HOME.
#
# Only condabin (`conda`, `mamba`) is on PATH, not /opt/conda/bin. The base env's python and pip
# would otherwise shadow the uv default interpreter below, and `pip install` into the root-owned
# base falls back to --user and litters ~/.local/lib. `conda activate` still puts an env's bin first.
ARG MINIFORGE_VERSION=26.9.4-2
ARG MINIFORGE_SHA256=bbaf16b3897da24c4be50315934ba74848f617b4495982841d6a0a60e0edbbdf
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/condabin:${PATH}
RUN curl -fsSL -o /tmp/miniforge.sh \
      "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" \
 && echo "${MINIFORGE_SHA256}  /tmp/miniforge.sh" | sha256sum -c - \
 && bash /tmp/miniforge.sh -b -p "${CONDA_DIR}" \
 && rm -f /tmp/miniforge.sh \
 && "${CONDA_DIR}/bin/conda" clean -afy

# System condarc: keep envs and package cache in the home so they persist across restarts, and
# make `conda activate` available in interactive bash for every user.
#
# Edited through `conda config --system`, never by writing the file directly. Miniforge ships its
# own /opt/conda/.condarc carrying `channels: [conda-forge]`, and overwriting it leaves conda with
# no channels at all, so every `conda create` fails with NoChannelsConfiguredError.
RUN conda config --system --prepend envs_dirs '~/.conda/envs' \
 && conda config --system --prepend pkgs_dirs '~/.conda/pkgs' \
 && conda config --system --show channels | grep -q conda-forge \
 && echo ". ${CONDA_DIR}/etc/profile.d/conda.sh" >> /etc/bash.bashrc

# --- uv ---------------------------------------------------------------------------------------
# Official static binaries copied from the upstream image. uv's cache defaults to ~/.cache/uv, in
# the home, so downloaded wheels/interpreters persist across restarts.
COPY --from=ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 /uv /uvx /usr/local/bin/

# uv's own completions, written to the bash-completion lookup dir so the loader sources them on
# first use of `uv`/`uvx` rather than in every shell startup.
RUN uv generate-shell-completion bash > /usr/share/bash-completion/completions/uv \
 && uvx --generate-shell-completion bash > /usr/share/bash-completion/completions/uvx

# The default `python`/`python3`: a uv-managed CPython linked into /usr/local/bin, ahead of Ubuntu's
# /usr/bin/python3. A researcher's own `uv python install --default` lands in ~/.local/bin, which
# env.sh puts first on PATH. The links target uv's per-minor directory, so venvs built on it
# survive patch upgrades but not a minor change: the minor is PINNED so a rebuild cannot break them.
# To move it, bump this ARG, release, and tell researchers to recreate venvs made from the default
# python. --default is still a uv preview feature, hence the explicit opt-in. The UV_* scoping is
# explained at the JupyterLab install below.
#
# uv links only the interpreters, so its `pip` is linked by hand. Otherwise bare `pip` is Ubuntu's
# /usr/bin/pip, which runs under Ubuntu's own python3 and disagrees with `python -m pip`. Outside a
# venv both refuse to install (PEP 668: uv marks its pythons externally managed), but this way the
# error points at uv rather than apt.
ARG PYTHON_VERSION=3.14
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    uv python install --default --preview-features python-install-default "${PYTHON_VERSION}" \
 && bin="$(dirname "$(readlink /usr/local/bin/python)")" \
 && for p in pip pip3 "pip${PYTHON_VERSION}"; do ln -s "${bin}/${p}" "/usr/local/bin/${p}"; done \
 && /usr/local/bin/python --version && /usr/local/bin/pip --version

# JupyterLab as an isolated uv tool, on PATH as /usr/local/bin/jupyter-lab. The start-up runs it.
#
# The UV_* settings are scoped to this RUN deliberately. As ENV they persist into the running
# workspace, where the owner's uid cannot write to root-owned /opt/uv, so any uv operation
# needing an interpreter download dies with
#   error: failed to create directory `/opt/uv/python`: Permission denied (os error 13)
# Unscoped, uv falls back to ~/.local/share/uv and ~/.local/bin, both in the home.
ARG JUPYTERLAB_VERSION=4.6.6
RUN UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv tool install "jupyterlab==${JUPYTERLAB_VERSION}" \
 && test -x /usr/local/bin/jupyter-lab

# nvitop: an interactive GPU process viewer, beside nvtop. It shows each process's GPU memory and
# its host CPU and memory in one view. Same isolated uv tool layout as JupyterLab.
ARG NVITOP_VERSION=1.7.2
RUN UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv tool install "nvitop==${NVITOP_VERSION}" \
 && nvitop --version

# --- Node.js ----------------------------------------------------------------------------------
# For the pi coding agent (Node >= 22.19) and for researchers: npx-run MCP servers, JS tooling,
# JupyterLab extension builds. Copied from the official image, like uv, rather than apt: Ubuntu's
# npm package drags in hundreds of node-* packages. 24 is the active LTS line (24.22.3 at this
# digest). The official linux-x64 build targets glibc 2.28, so it runs unchanged on 26.04.
COPY --from=node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 /usr/local/bin/node /usr/local/bin/
COPY --from=node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && node --version && npm --version

# `npm install -g` as the workspace uid would otherwise fail EACCES against root-owned /usr/local.
# The global npmrc (read from <node prefix>/etc/npmrc) points user installs at ~/.local, whose bin
# dir env.sh puts on PATH and which persists in the home. Image-time installs as root pass
# --prefix /usr/local explicitly.
RUN mkdir -p /usr/local/etc \
 && echo 'prefix=${HOME}/.local' > /usr/local/etc/npmrc

# --- browser tools ----------------------------------------------------------------------------
# Each listens on localhost only, behind the per-URL sign-in proxy the platform puts in front of it;
# the start-up decides which run, on which port and under which path.
#   ttyd            a terminal in the browser
#   code-server     VS Code in the browser (MIT, from the Coder project; needs nothing from Coder)
#   filebrowser     File Browser Quantum, a web file manager: upload and download (folders as
#                   zip), move, rename, preview. The gtsteffaniak fork: the original
#                   filebrowser/filebrowser is archived
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
RUN curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" \
 && echo "${TTYD_SHA256}  /usr/local/bin/ttyd" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/ttyd \
 && ttyd --version

ARG CODE_SERVER_VERSION=4.145.2
ARG CODE_SERVER_SHA256=7eddbdeaab34380bde3ac3bbadce58fe2f5722c4877f331ea593ae797c2517e1
RUN curl -fsSL -o /tmp/code-server.deb \
      "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb" \
 && echo "${CODE_SERVER_SHA256}  /tmp/code-server.deb" | sha256sum -c - \
 && dpkg -i /tmp/code-server.deb \
 && rm -f /tmp/code-server.deb \
 && code-server --version

ARG FILEBROWSER_VERSION=2.0.2-stable
ARG FILEBROWSER_SHA256=5710dc6f51d77f1db884eace44f6952286c49f2ce40b6a59af37e0dc7c4a8bbd
RUN curl -fsSL -o /usr/local/bin/filebrowser \
      "https://github.com/gtsteffaniak/filebrowser/releases/download/v${FILEBROWSER_VERSION}/linux-amd64-filebrowser" \
 && echo "${FILEBROWSER_SHA256}  /usr/local/bin/filebrowser" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/filebrowser \
 && filebrowser version

# --- command-line tools from upstream releases ------------------------------------------------
#   gh              GitHub CLI. Ubuntu's package lags well behind
#   websocat        WebSocket client/server: SSH carried over an HTTPS URL, beside PAIS Connect
ARG GH_VERSION=2.104.0
ARG GH_SHA256=98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e
RUN curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
 && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/gh.tar.gz --no-same-owner --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh" \
 && rm -f /tmp/gh.tar.gz \
 && gh completion -s bash > /usr/share/bash-completion/completions/gh \
 && gh --version

ARG WEBSOCAT_VERSION=1.14.2
ARG WEBSOCAT_SHA256=cd26f92cb507f620e2d54fe6e126f4dc191f3eee90f2b53bccf07eac0645ec84
RUN curl -fsSL -o /usr/local/bin/websocat \
      "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.x86_64-unknown-linux-musl" \
 && echo "${WEBSOCAT_SHA256}  /usr/local/bin/websocat" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/websocat \
 && websocat --version

# --- opencode (coding agent) -----------------------------------------------------------------
# The upstream release binary (self-contained, bundles its provider SDKs) into /usr/local/bin. Not
# the opencode.ai/install script: that installs to ~/.opencode/bin, and the workspace home is the
# researcher's, not the image's. The plain x64 build needs AVX2, which every PAIS node has; the
# -baseline build is for CPUs without. 1.19 is the line upstream marks latest; 2.x is released
# beside it.
#
# PINNED because a rebuild should not silently change the agent researchers are using. Root-owned,
# so its self-update cannot replace it: patch releases fail silently and minor/major ones show an
# "update available" notice. OPENCODE_DISABLE_AUTOUPDATE is deliberately NOT set, because as a
# process-wide env var it would also stop a copy a researcher installed in their own home from
# updating itself.
ARG OPENCODE_VERSION=1.19.5
ARG OPENCODE_SHA256=588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a
RUN curl -fsSL -o /tmp/opencode.tar.gz \
      "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
 && echo "${OPENCODE_SHA256}  /tmp/opencode.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/opencode.tar.gz --no-same-owner -C /usr/local/bin opencode \
 && rm -f /tmp/opencode.tar.gz \
 && opencode --version

# The PAIS provider, layered via OPENCODE_CONFIG so nothing is written to the home. opencode MERGES
# its config layers (global ~/.config/opencode < OPENCODE_CONFIG < project opencode.json), so a
# researcher's own config keeps working alongside this. The layer sits ABOVE their global config,
# so it defines only the `pais` provider and never `model` or other preferences, which would
# override theirs. Not /etc/opencode: that is opencode's managed-settings dir, which no user layer
# can override.
#
# It also disables two built-in providers. `openai` turns itself on whenever OPENAI_API_KEY is set,
# and here that variable holds the PAIS key, so every model it lists would fail against
# api.openai.com. `opencode` is opencode's hosted Zen service (free models such as Big Pickle,
# needing no key), which would send prompts and code outside PAIS. With both gone, `pais` is the
# only connected provider and becomes the default without setting `model`. Config arrays REPLACE
# rather than concatenate, so a researcher re-enables these only from a project opencode.json or
# their own OPENCODE_CONFIG, not from ~/.config/opencode. Every value is an {env:...} reference:
# LLM_API_BASE and LLM_MODEL come from the workload, OPENAI_API_KEY is the researcher's own, so a
# gateway change is a template change, not an image release.
COPY opencode.json /etc/pais/opencode.json
ENV OPENCODE_CONFIG=/etc/pais/opencode.json

# --- pi (coding agent) ------------------------------------------------------------------------
# From npm into /usr/local, PINNED for the same reason as opencode. fd and rg, which pi otherwise
# downloads into ~/.pi on first use, are in the apt list above.
#
# pi has no system-wide config layer: models.json, settings.json, auth.json and sessions all live
# in ~/.pi/agent. The PAIS provider is therefore an extension (pi/pais.ts) that the /usr/local/bin/pi
# wrapper loads with `-e`, which adds to the researcher's own extensions rather than replacing them,
# and nothing is written to the home. A pi the researcher installs themselves (npm -g lands in
# ~/.local, ahead on PATH) runs without the wrapper and so without the provider.
#
# PI_SKIP_VERSION_CHECK hides the "update available" notice for this root-owned copy. Not
# PI_OFFLINE: that also stops pi installing and updating the researcher's own pi packages.
ARG PI_VERSION=1.5.2
RUN npm install -g --prefix /usr/local "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force \
 && rm /usr/local/bin/pi
COPY pi/pais.ts /opt/pais/pi/pais.ts
COPY --chmod=0755 pi/pi /usr/local/bin/pi
RUN pi --version
ENV PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

# --- Claude Code (coding agent) ---------------------------------------------------------------
# The native release binary from Anthropic's release bucket (what claude.ai/install.sh downloads),
# checked against the SHA-256 in that version's manifest.json. The `stable` channel's version.
# Unconfigured: sign-in or API key is the researcher's own.
#
# PINNED and root-owned, like opencode and pi. The /usr/local/bin/claude wrapper turns the
# auto-updater off for this copy only: it cannot replace itself, and DISABLE_AUTOUPDATER as image
# ENV would also stop a copy the researcher installs in their home (~/.local/bin, ahead on PATH).
ARG CLAUDE_CODE_VERSION=2.1.311
ARG CLAUDE_CODE_SHA256=86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada
RUN mkdir -p /opt/claude-code \
 && curl -fsSL -o /opt/claude-code/claude \
      "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-x64/claude" \
 && echo "${CLAUDE_CODE_SHA256}  /opt/claude-code/claude" | sha256sum -c - \
 && chmod 0755 /opt/claude-code/claude \
 && printf '#!/bin/sh\nDISABLE_AUTOUPDATER=1 exec /opt/claude-code/claude "$@"\n' > /usr/local/bin/claude \
 && chmod 0755 /usr/local/bin/claude \
 && claude --version

# Last, so the build's own RUN steps don't source env.sh.
ENV BASH_ENV=/etc/pais/env.sh

USER nobody
