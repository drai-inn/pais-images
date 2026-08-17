# pais-slicer-desktop: 3D Slicer over a remote desktop, with hardware OpenGL, for Coder workspaces.
#
# Everything here exists so the WORKSPACE NEEDS NO ROOT AT RUNTIME. The `slicer` template runs with
# allow_privilege_escalation = false, which sets the kernel's no_new_privs flag and makes sudo fail
# outright ("sudo: The 'no new privileges' flag is set"). The Coder KasmVNC module installs a .deb
# with sudo on every start, so without baking it the desktop simply never comes up. Same story for
# VirtualGL and Slicer itself.
#
# Built on codercom/enterprise-desktop:ubuntu-noble, which is enterprise-base (UID-1000 `coder`,
# HOME=/home/coder, git/curl/sudo) plus XFCE. It does NOT contain a VNC server; that comes from the
# KasmVNC package below.
#
# ⚠️ NOBLE (24.04) IS PINNED DELIBERATELY. The `:ubuntu` tag is currently Ubuntu 26.04 "resolute",
# and KasmVNC publishes debs for focal/jammy/noble/bookworm/bullseye only. The Coder module builds
# its download URL from $VERSION_CODENAME, so on resolute it 404s. Verified against the upstream
# release asset list 2026-08-17. Date-stamped tags (ubuntu-noble-YYYYMMDD) exist if we ever want
# full build reproducibility; the codename pin is the part that actually matters here.
FROM codercom/enterprise-desktop:ubuntu-noble

USER root

ARG SLICER_VERSION=5.12.3
ARG SLICER_REVISION=34627
# Version-specific bitstream id and checksum from https://download.slicer.org/find?os=linux&arch=amd64&stability=release
ARG SLICER_BITSTREAM=6a6159372eb3d967f032505f
ARG SLICER_SHA512=66bd3a1b9a7f636b40b96cb8c49f395ee783cdcaf7b43a4b895d6a40df9e0af8393f5ab7631ba50f6bbe06aa17dbcd8a46984a53b693bdf203d34337e2e80401
ARG KASMVNC_VERSION=1.5.0
ARG VIRTUALGL_VERSION=3.1.4

# --- timezone ---------------------------------------------------------------------------------
# Same rationale as datasci-cpu: the base is UTC and researchers are in NZ.
ENV TZ=Pacific/Auckland
RUN ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
 && echo "${TZ}" > /etc/timezone

# --- Slicer's system dependencies -------------------------------------------------------------
# This exact list was derived empirically on this image by launching Slicer in a loop and reading
# the launcher's own "error while loading shared libraries" output, 17 rounds until it started.
#
# Do NOT try to shorten it by reading `ldd` output: Slicer bundles ~400 of its own .so files that
# only resolve under its launcher's LD_LIBRARY_PATH, so a plain ldd sweep reports 391 false
# "not found" entries and hides the handful that matter.
#
# mesa-utils is not a Slicer dependency. It provides glxinfo/eglinfo, which is how you diagnose
# "why is this rendering at 2 fps" in a live workspace, so it is worth the few MB.
# libxv1 is required by VirtualGL.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      libasound2t64 \
      libgl1 \
      libglu1-mesa \
      libnss3 \
      libopengl0 \
      libpcre2-16-0 \
      libxcb-icccm4 \
      libxcb-image0 \
      libxcb-keysyms1 \
      libxcb-randr0 \
      libxcb-render-util0 \
      libxcb-shape0 \
      libxcb-sync1 \
      libxcb-xfixes0 \
      libxcb-xinerama0 \
      libxcb-xkb1 \
      libxkbcommon-x11-0 \
      libxv1 \
      mesa-utils \
 && rm -rf /var/lib/apt/lists/*

# --- KasmVNC ----------------------------------------------------------------------------------
# Baked so the Coder module's `check_installed()` short-circuits and never reaches its sudo
# apt-get. Everything the module does after that point (write config, kasmvncpasswd, start the
# server) works fine as an unprivileged user.
RUN curl -fsSL -o /tmp/kasmvncserver.deb \
      "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_amd64.deb" \
 && apt-get update \
 && apt-get install --yes --no-install-recommends /tmp/kasmvncserver.deb \
 && rm -f /tmp/kasmvncserver.deb \
 && rm -rf /var/lib/apt/lists/*

# ⚠️ THIS chown IS LOAD-BEARING, do not remove it as tidy-up.
#
# The template sets `subdomain = false` (no wildcard access URL on this deployment). In that mode
# the KasmVNC module rewrites the served web root: it moves path_vnc.html into httpd_directory and
# re-points index.html at it, using `$SUDO`. With no sudo available $SUDO is empty, so those writes
# land in root-owned /usr/share/kasmvnc/www as uid 1000 and fail with EPERM, which fails the whole
# startup script and flags the workspace as incomplete.
#
# Giving `coder` ownership of the web root lets the unprivileged path succeed. This is the served
# static UI only, not configuration or credentials.
RUN chown -R coder:coder /usr/share/kasmvnc/www

# --- VirtualGL --------------------------------------------------------------------------------
# KasmVNC's Xvnc is a software X server with no GPU attachment, so GLX resolves to libGLX_mesa and
# renders on llvmpipe even when the nvidia GL stack is present in the container. VirtualGL's EGL
# backend redirects GLX onto the card. Measured on an A40: 2.01 fps -> 59.65 fps for Slicer volume
# rendering. See the launcher below for the -nodl flag, which is not optional.
RUN curl -fsSL -o /tmp/virtualgl.deb \
      "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION}/virtualgl_${VIRTUALGL_VERSION}_amd64.deb" \
 && apt-get update \
 && apt-get install --yes --no-install-recommends /tmp/virtualgl.deb \
 && rm -f /tmp/virtualgl.deb \
 && rm -rf /var/lib/apt/lists/*

# --- 3D Slicer --------------------------------------------------------------------------------
# Baked into the image rather than the home PVC on purpose: it is 1.7 GB unpacked, the PVC is
# quota-bound per researcher, and image layers are shared. The container sets
# image_pull_policy = Always, so a rebuilt image reaches workspaces on their next restart.
#
# Pinned to an exact bitstream id and verified by checksum. The /find endpoint's "latest release"
# answer moves, and an unpinned image would silently change Slicer version between rebuilds.
RUN curl -fsSL -o /tmp/slicer.tar.gz \
      "https://download.slicer.org/bitstream/${SLICER_BITSTREAM}" \
 && echo "${SLICER_SHA512}  /tmp/slicer.tar.gz" | sha512sum --check --strict \
 && mkdir -p /opt/slicer \
 && tar -xzf /tmp/slicer.tar.gz -C /opt/slicer --strip-components=1 \
 && rm -f /tmp/slicer.tar.gz \
 && test -x /opt/slicer/Slicer \
 && test -x /opt/slicer/bin/PythonSlicer

# trimesh into Slicer's own interpreter. Pure Python, so it installs cleanly.
#
# open3d is deliberately absent and CANNOT be added. Slicer ships a generated _manylinux.py that
# hard-codes a glibc 2.28 ceiling to avoid ABI-mismatch crashes, so its pip advertises
# manylinux_2_28 as its maximum whatever the host glibc is. open3d 0.19.0 is the only release with
# cp312 wheels and is tagged manylinux_2_31; every release back to 0.18.0 is manylinux_2_27 but
# stops at cp311. Nothing satisfies both, and `pip install open3d` fails with "No matching
# distribution found". Verified 2026-08-17. Do not "fix" this by editing the shim.
RUN /opt/slicer/bin/PythonSlicer -m pip install --no-cache-dir --no-input trimesh \
 && /opt/slicer/bin/PythonSlicer -c "import trimesh; print(trimesh.__version__)"

# --- launcher ---------------------------------------------------------------------------------
# Researchers must not be expected to know about vglrun, let alone its -nodl flag, so the GPU path
# is wrapped here and `slicer` is the only command anyone needs.
#
# -nodl is REQUIRED. Plain `vglrun` dies with `[VGL] ERROR: Could not load function "dlopen"`,
# which comes from VirtualGL's libdlfaker.so on this glibc. -nodl skips that faker. (A HAMi
# libvgpu.so "recursive dlsym : dlopen" warning appears alongside and is a red herring; the failure
# reproduces with LD_PRELOAD empty.)
#
# The GPU test is real, not defensive: this same image serves CPU-only workspaces, where
# libGLX_nvidia is absent and `vglrun -d egl` would fail rather than fall back on its own.
RUN printf '%s\n' \
      '#!/bin/sh' \
      '# 3D Slicer launcher. Uses the GPU via VirtualGL when one is attached, software GL otherwise.' \
      'if [ -e /usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.0 ] && [ -d /dev/dri ]; then' \
      '  exec vglrun -nodl -d egl /opt/slicer/Slicer "$@"' \
      'fi' \
      'echo "slicer: no NVIDIA GL stack found, falling back to software rendering (expect ~2 fps in 3D views)." >&2' \
      'exec /opt/slicer/Slicer "$@"' \
      > /usr/local/bin/slicer \
 && chmod 0755 /usr/local/bin/slicer

# XFCE menu entry, so Slicer is launchable from the desktop and not only the terminal.
RUN printf '%s\n' \
      '[Desktop Entry]' \
      'Type=Application' \
      'Name=3D Slicer' \
      "Comment=Medical image computing platform (${SLICER_VERSION})" \
      'Exec=/usr/local/bin/slicer' \
      'Icon=/opt/slicer/Slicer.png' \
      'Terminal=false' \
      'Categories=Graphics;Science;MedicalSoftware;' \
      > /usr/share/applications/slicer.desktop

USER coder
