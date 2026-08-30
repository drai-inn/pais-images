# pais-slicer-desktop: 3D Slicer over a remote desktop, with hardware OpenGL, for Coder workspaces.
#
# Everything here exists so the WORKSPACE NEEDS NO ROOT AT RUNTIME. The `slicer` template runs with
# allow_privilege_escalation = false, which sets the kernel's no_new_privs flag and makes sudo fail
# outright ("sudo: The 'no new privileges' flag is set"). The Coder KasmVNC module installs a .deb
# with sudo on every start, so without baking it the desktop simply never comes up. Same story for
# VirtualGL and Slicer itself.
#
# Three stages:
#   base            everything shared: system deps, KasmVNC, VirtualGL, Slicer itself
#   open3d-builder  compiles open3d against Slicer's bundled Python and emits a wheel
#   runtime         base + that wheel + trimesh + the launcher. This is what ships.
#
# The builder exists only because open3d cannot be pip installed into Slicer; see its stage header.
# None of the toolchain or the ~3 GB open3d build tree reaches the runtime stage.
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

# Declared before the first FROM so both `base` and `runtime` can pick it up with a bare ARG.
ARG SLICER_VERSION=5.12.3

# ==================================================================================================
# base
# ==================================================================================================
FROM codercom/enterprise-desktop:ubuntu-noble AS base

USER root

ARG SLICER_VERSION
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

# ==================================================================================================
# open3d-builder
# ==================================================================================================
# open3d CANNOT be pip installed into Slicer. Slicer ships a generated `_manylinux.py` that
# hard-codes a glibc 2.28 ceiling, so its pip advertises manylinux_2_28 as its maximum whatever the
# host glibc actually is. open3d 0.19.0 is the only release with cp312 wheels and is tagged
# manylinux_2_31; every release back to 0.18.0 is manylinux_2_27 but stops at cp311. Nothing
# satisfies both, and `pip install open3d` fails with "No matching distribution found". Verified
# 2026-08-17. Do not "fix" this by editing the shim.
#
# Building it here is a different proposition. That ceiling exists to stop wheels compiled against a
# newer libstdc++/glibc ABI from crashing Slicer, and Slicer bundles neither libstdc++ nor libgcc, it
# links the system ones. Compiling against this exact base therefore produces a wheel with the same
# ABI Slicer itself runs on, which is the thing the ceiling is trying to guarantee.
#
# Verified in-process on 2026-08-18, not merely imported: open3d 0.19.0 loads inside a running Slicer
# 5.12.3 alongside its own Qt5, VTK 9.6 and ITK, with no symbol clash; geometry, voxel downsampling
# and ICP registration all run; and the resulting vertices round-trip into a vtkMRMLModelNode.
#
# (On aarch64 the PyPI version matrix does line up, which is why open3d already pip installs in
# Slicer on the researcher's IGX and this stage is an x86_64 problem only.)
FROM base AS open3d-builder

ARG OPEN3D_VERSION=v0.19.0
ARG CPYTHON_VERSION=3.12.10
# Checksum computed from this URL on 2026-08-19. Pinned to detect the tarball changing under us,
# same rationale as the Slicer bitstream pin above.
ARG CPYTHON_SHA256=15d9c623abfd2165fe816ea1fb385d6ed8cf3c664661ab357f1782e3036a6dac

# ⚠️ THE WAYLAND PACKAGES ARE NOT OPTIONAL, despite BUILD_GUI=OFF and despite this never rendering
# anything. BUILD_GUI=OFF drops filament and O3DVisualizer but NOT the legacy Visualizer, which open3d
# still builds, and that pulls in glfw as an ExternalProject. glfw 3.4 defaults GLFW_BUILD_WAYLAND=ON
# on Linux and open3d does not pass anything to turn it off, so glfw's configure hard-fails with
# "Failed to find wayland-scanner" about 27 seconds in. wayland-scanner comes from libwayland-bin.
#
# The X11 and OSMesa dev packages are in the same category: unused at runtime, required to configure.
# Nothing in this stage reaches the runtime image, so trimming any of it buys nothing.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      autoconf \
      build-essential \
      cmake \
      libglu1-mesa-dev \
      libosmesa6-dev \
      libtbb-dev \
      libtool \
      libudev-dev \
      libwayland-bin \
      libwayland-dev \
      libx11-dev \
      libxcursor-dev \
      libxi-dev \
      libxinerama-dev \
      libxkbcommon-dev \
      libxrandr-dev \
      ninja-build \
      pkg-config \
      wayland-protocols \
 && rm -rf /var/lib/apt/lists/*

# --- reconstruct Slicer's Python include tree -------------------------------------------------
# Slicer strips its own include dir down to pyconfig.h alone, so out of the box there is nothing to
# compile an extension against. pyconfig.h is the only header whose contents depend on how that
# interpreter was configured, so pairing Slicer's copy of it with the generic Include/ tree from the
# EXACTLY matching CPython source release reconstructs a coherent tree. CPython's Include/ contains
# no pyconfig.h, so copying it in place leaves Slicer's own file untouched.
#
# ⚠️ The headers must land in Slicer's OWN include dir. open3d's pybind target reads the legacy
# PYTHON_INCLUDE_DIRS, which CMake derives by asking the interpreter where its headers live, so it
# ignores a side directory passed via -DPython3_INCLUDE_DIR. That flag is still set below so the
# modern FindPython3 path agrees with the legacy one.
RUN test -f /opt/slicer/lib/Python/include/python3.12/pyconfig.h \
 && curl -fsSL -o /tmp/cpython.tgz \
      "https://www.python.org/ftp/python/${CPYTHON_VERSION}/Python-${CPYTHON_VERSION}.tgz" \
 && echo "${CPYTHON_SHA256}  /tmp/cpython.tgz" | sha256sum --check --strict \
 && tar -xzf /tmp/cpython.tgz -C /tmp \
 && cp -r "/tmp/Python-${CPYTHON_VERSION}/Include/." /opt/slicer/lib/Python/include/python3.12/ \
 && rm -rf /tmp/cpython.tgz "/tmp/Python-${CPYTHON_VERSION}" \
 && test -f /opt/slicer/lib/Python/include/python3.12/Python.h

# Compile the smallest possible extension against the reconstructed tree and load it into Slicer's
# interpreter. An incoherent header tree then fails here in seconds instead of an hour into open3d.
RUN printf '%s\n' \
      '#include <Python.h>' \
      'static PyMethodDef M[] = {{NULL, NULL, 0, NULL}};' \
      'static struct PyModuleDef mod = {PyModuleDef_HEAD_INIT, "probe", NULL, -1, M};' \
      'PyMODINIT_FUNC PyInit_probe(void) { return PyModule_Create(&mod); }' \
      > /tmp/probe.c \
 && gcc -shared -fPIC -I/opt/slicer/lib/Python/include/python3.12 \
      /tmp/probe.c -o /tmp/probe.cpython-312-x86_64-linux-gnu.so \
 && PYTHONPATH=/tmp /opt/slicer/bin/PythonSlicer -c "import probe" \
 && rm -f /tmp/probe.c /tmp/probe.cpython-312-x86_64-linux-gnu.so

# --- build open3d -----------------------------------------------------------------------------
# BUILD_GUI=OFF drops filament, by far the largest dependency, and with it draw_geometries and
# O3DVisualizer. A Slicer widget renders in Slicer's own 3D views, so neither is wanted. CUDA is off
# because the GPU here serves OpenGL through VirtualGL and the compute question is a separate one.
# WebRTC off follows from GUI off. With CUDA off the package names itself open3d-cpu, not open3d.
RUN git clone --depth 1 --branch "${OPEN3D_VERSION}" --recurse-submodules --shallow-submodules \
      https://github.com/isl-org/Open3D.git /opt/open3d \
 && cmake -S /opt/open3d -B /opt/open3d-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DPython3_EXECUTABLE=/opt/slicer/bin/PythonSlicer \
      -DPython3_INCLUDE_DIR=/opt/slicer/lib/Python/include/python3.12 \
      -DPython3_LIBRARY=/opt/slicer/lib/Python/lib/libpython3.12.so \
      -DBUILD_PYTHON_MODULE=ON \
      -DBUILD_GUI=OFF \
      -DBUILD_CUDA_MODULE=OFF \
      -DBUILD_WEBRTC=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_UNIT_TESTS=OFF \
      -DBUILD_BENCHMARKS=OFF \
      -DWITH_OPENMP=ON \
 && cmake --build /opt/open3d-build --target pip-package -j "$(nproc)"

# ⚠️ THE IRONY IS REAL AND THIS RETAG IS REQUIRED. The wheel just built is tagged manylinux_2_39,
# because 2.39 is this base's glibc, and Slicer's own 2.28 shim rejects it exactly as it rejects
# PyPI's. `wheel tags` rewrites both the filename and the internal WHEEL metadata to linux_x86_64,
# a tag that makes no glibc claim and so never reaches the shim. That is also the honest tag: this
# wheel is built for this image and is not portable off it.
RUN mkdir -p /out \
 && cp /opt/open3d-build/lib/python_package/pip_package/open3d_cpu-*.whl /out/ \
 && /opt/slicer/bin/PythonSlicer -m wheel tags \
      --platform-tag linux_x86_64 --remove /out/open3d_cpu-*.whl \
 && ls -1 /out

# ==================================================================================================
# runtime
# ==================================================================================================
FROM base AS runtime

ARG SLICER_VERSION

# trimesh is pure Python and installs cleanly. open3d comes from the builder stage above.
#
# ⚠️ open3d is NOT a self-contained addition. `import open3d` unconditionally imports
# open3d.visualization, which imports draw_plotly, which imports plotly and then dash at module
# load. Neither is optional and BUILD_GUI=OFF does not remove them, because it is a Python-side
# import rather than a compiled feature. Removing them would mean forking
# open3d/visualization/__init__.py.
#
# The measured cost is 31 added packages and site-packages growing 711 MB -> 998 MB, of which plotly
# is 68 MB, dash 40 MB and open3d itself 154 MB. Verified 2026-08-19 by diffing dist-info against
# the previous release: all 31 are pure additions and nothing Slicer already shipped was overwritten
# or downgraded, so this widens the dependency surface without conflicting with Slicer's own
# environment. If open3d turns out to be unwanted, dropping this stage reverts all of it.
COPY --from=open3d-builder /out/*.whl /tmp/wheels/
RUN /opt/slicer/bin/PythonSlicer -m pip install --no-cache-dir --no-input \
      trimesh /tmp/wheels/*.whl \
 && rm -rf /tmp/wheels \
 && /opt/slicer/bin/PythonSlicer -c "\
import numpy as np, trimesh, open3d as o3d; \
m = o3d.geometry.TriangleMesh.create_sphere(radius=1.0); m.compute_vertex_normals(); \
p = o3d.geometry.PointCloud(o3d.utility.Vector3dVector(np.asarray(m.vertices))); \
print('trimesh', trimesh.__version__, '| open3d', o3d.__version__, '|', m, '|', p)"

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
