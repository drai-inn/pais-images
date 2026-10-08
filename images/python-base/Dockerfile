# python-base: general Python + R research workbench base image for Coder workspaces.
#
# Renamed from datasci-cpu 2026-09-14. The old name said "cpu" while the template offers a GPU and
# the driver arrives by runtime injection regardless of what is baked, so it was actively wrong. The
# GHCR package ghcr.io/drai-inn/pais-images/datasci-cpu is left published for anything still
# pulling it; GHCR packages cannot be renamed, so this publishes a new one.
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
# vim, man and openssh-client. This is the interactive environment researchers land in and there is
# NO sudo (restricted PSA drops ALL capabilities and sets no_new_privs), so anything absent here
# cannot be added by the user later. The set below was reconciled against NeSI's OOD base image
# (nesi/nesi-ood-base ansible/roles/nesi.compute/defaults/main.yml) on 2026-09-26, keeping what
# suits a container workbench and dropping what only makes sense on a bare-metal HPC node.
#
# Session and shell:
#   tmux            the Coder web terminal drops its session on reload, killing long conda solves,
#   screen          uv syncs and model fits; these let researchers detach instead
#   bash-completion the completion loader itself (see the shell defaults section below)
#   zsh fish        the login shell stays /bin/bash: it is hardcoded in the template's nss_wrapper
#   tcsh ksh        passwd entry and there is no chsh without root. These are for `exec zsh` and
#                   for scripts with a non-bash shebang, NOT a way to change your default shell.
#
# Editors:
#   nano            vim is the base image's only editor and owns the `editor` alternative, so an
#                   unset EDITOR drops researchers into vim at their first `git commit`
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
# Monitoring (a workspace can hold a whole GPU and up to 256 GiB, and the cgroup limit is the
# only thing standing between a researcher and a failed build, so this is not idle curiosity):
#   nvtop           the GPU equivalent of htop. 0.1 MB, and there was no GPU monitor at all
#   btop            nicer htop, and the one most people now expect
#   sysstat         iostat/pidstat/mpstat. Home AND scratch are both NFS on VAST, so "is it me or
#                   is it the filesystem" is otherwise unanswerable from inside the pod
#   numactl         the H200 nodes are dual-socket; pinning matters for memory-bound work
#   hwloc           lstopo. NB it reports the NODE topology, not the cgroup's slice of it
#   pciutils        lspci, to see which GPU was actually injected
#   time            /usr/bin/time -v gives peak RSS, which is how you pick between the 64, 128 and
#                   256 GiB options. Bash's `time` builtin shadows it: use `\time -v` or the path
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
#   ncdu            the home PVC is quota-bound and conda envs / uv caches fill it; researchers
#                   need to see what is eating the volume
#   pigz            parallel gzip; a workspace has up to 16 cores and tar.gz is still the default
#   p7zip-full      provides `7z`, for archives that turn up from collaborators
#   zip
#   zstd            the base ships none, and /opt/conda/bin (which has one) is not on PATH
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
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      aria2 \
      autoconf \
      automake \
      bash-completion \
      bc \
      bison \
      btop \
      cmake \
      datamash \
      dos2unix \
      fd-find \
      file \
      fish \
      flex \
      gdb \
      gfortran \
      git-lfs \
      graphviz \
      hwloc \
      imagemagick \
      ksh \
      lftp \
      libtool \
      libtool-bin \
      lsof \
      ltrace \
      m4 \
      nano \
      ncdu \
      netcat-openbsd \
      numactl \
      nvtop \
      p7zip-full \
      pandoc \
      parallel \
      patchelf \
      pciutils \
      pigz \
      pkg-config \
      psmisc \
      rclone \
      ripgrep \
      screen \
      strace \
      swig \
      sysstat \
      tcsh \
      time \
      tmux \
      tree \
      universal-ctags \
      zip \
      zsh \
      zstd \
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
#
# Only condabin (`conda`, `mamba`) is on PATH, not /opt/conda/bin. The base env's python and pip
# would otherwise shadow the uv default interpreter below, and `pip install` into the root-owned
# base falls back to --user and litters ~/.local/lib. `conda activate` still puts an env's bin first.
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/condabin:${PATH}
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

# The default `python`/`python3`: a uv-managed CPython linked into /usr/local/bin, ahead of Ubuntu's
# /usr/bin/python3. A researcher's own `uv python install --default` lands in ~/.local/bin, which
# precedes it. The links target uv's per-minor directory, so venvs built on it survive patch
# upgrades but not a minor change: the minor is PINNED so a rebuild cannot break them. To move it,
# bump this ARG, release, and tell researchers to recreate venvs made from the default python.
# --default is still a uv preview feature, hence the explicit opt-in. The UV_* scoping is explained
# at the JupyterLab install below.
ARG PYTHON_VERSION=3.14
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    uv python install --default --preview-features python-install-default "${PYTHON_VERSION}" \
 && /usr/local/bin/python --version

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

# --- Node.js ----------------------------------------------------------------------------------
# For the pi coding agent (Node >= 22.19) and for researchers: npx-run MCP servers, JS tooling,
# JupyterLab extension builds. Copied from the official image, like uv, rather than apt: Ubuntu's
# npm package drags in hundreds of node-* packages. 24 is the active LTS line. The official
# linux-x64 build targets glibc 2.28, so it runs unchanged on 26.04.
COPY --from=node:24-slim /usr/local/bin/node /usr/local/bin/
COPY --from=node:24-slim /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && node --version && npm --version

# `npm install -g` as the workspace uid would otherwise fail EACCES against root-owned /usr/local.
# The global npmrc (read from <node prefix>/etc/npmrc) points user installs at ~/.local, whose bin
# dir is already on PATH below and which persists on the home PVC. Image-time installs as root pass
# --prefix /usr/local explicitly.
RUN mkdir -p /usr/local/etc \
 && echo 'prefix=${HOME}/.local' > /usr/local/etc/npmrc

# --- opencode (coding agent) -----------------------------------------------------------------
# The upstream release binary (self-contained, bundles its provider SDKs) into /usr/local/bin. Not
# the opencode.ai/install script: that installs to ~/.opencode/bin, which the home mount masks.
# The plain x64 build needs AVX2, which every PAIS node has; the -baseline build is for CPUs without.
#
# PINNED because a rebuild should not silently change the agent researchers are using. Root-owned,
# so its self-update cannot replace it: patch releases fail silently and minor/major ones show an
# "update available" notice. OPENCODE_DISABLE_AUTOUPDATE is deliberately NOT set, because as a
# process-wide env var it would also stop a copy a researcher installed in their own home from
# updating itself. To move the version, bump this ARG and release the image.
ARG OPENCODE_VERSION=1.18.34
RUN curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
      | tar -xz --no-same-owner -C /usr/local/bin opencode \
 && opencode --version

# The PAIS provider, layered via OPENCODE_CONFIG so nothing is written to the home. opencode MERGES
# its config layers (global ~/.config/opencode < OPENCODE_CONFIG < project opencode.json), so a
# researcher's own config keeps working alongside this. The layer sits ABOVE their global config,
# so it defines only the `pais` provider and never `model` or other preferences, which would
# override theirs. Not /etc/opencode: that is opencode's managed-settings dir, which no user layer
# can override. Every value is an {env:...} reference to what the template injects (LLM_API_BASE,
# LLM_MODEL) or the researcher's Coder user secret (OPENAI_API_KEY), so a gateway change is a
# template change, not an image release.
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
ARG PI_VERSION=1.0.4
RUN npm install -g --prefix /usr/local "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force \
 && rm /usr/local/bin/pi
COPY pi/pais.ts /opt/pais/pi/pais.ts
COPY --chmod=0755 pi/pi /usr/local/bin/pi
RUN pi --version
ENV PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

# --- buzz -------------------------------------------------------------------------------------
# `buzz` (CLI) and `buzz-acp` (ACP harness bridging Buzz events to an agent such as
# `opencode acp`). block/buzz publishes no standalone CLI release; both binaries ship inside the
# Linux desktop .deb, so they are extracted from it rather than built from source. They link
# only against glibc (<= 2.39). Installed unconfigured: relay URL, keys and allowlists are the
# researcher's own (BUZZ_* env vars, e.g. via Coder user secrets).
ARG BUZZ_VERSION=0.5.26
RUN curl -fsSL -o /tmp/buzz.deb \
      "https://github.com/block/buzz/releases/download/desktop-v${BUZZ_VERSION}/Buzz_${BUZZ_VERSION}_amd64.deb" \
 && dpkg-deb -x /tmp/buzz.deb /tmp/buzz \
 && install -m 0755 /tmp/buzz/usr/bin/buzz /tmp/buzz/usr/bin/buzz-acp /usr/local/bin/ \
 && rm -rf /tmp/buzz.deb /tmp/buzz \
 && buzz --help >/dev/null && buzz-acp --help >/dev/null

# uv's default tool bin dir at runtime. Deliberately not created here: the home PVC mounts over
# /home/coder and masks anything the image writes there, so the entry resolves only once uv makes
# it. A non-existent PATH entry is harmless meanwhile.
ENV PATH=/home/coder/.local/bin:${PATH}

USER coder
