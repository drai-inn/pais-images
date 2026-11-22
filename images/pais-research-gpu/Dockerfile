# pais-research-gpu: pais-research plus the common GPU / machine-learning Python stack, in the default
# Python (`python`, the uv-managed CPython in /usr/local/bin), versions pinned in requirements.txt.
#
# Why in the default Python and not a separate venv: everyone gets `import torch` with nothing to
# install, JupyterLab gets a kernel for it, and a researcher's own environment can build on it without
# downloading torch again:  uv venv --system-site-packages .venv  (their own packages go in .venv;
# the image's stay read-only).
#
# torch from PyPI bundles its CUDA runtime (cu13 wheels); the driver and nvidia-smi come from the GPU
# node at run time, as for pais-base. Large: several GB more than pais-research.
#
# BASE is the pais-research version to build on; CI passes the one in ../pais-research/VERSION.
ARG BASE=ghcr.io/drai-inn/pais-images/pais-research:pais-research-v1
FROM ${BASE}

USER root
SHELL ["/usr/bin/env", "-u", "BASH_ENV", "/bin/bash", "-o", "pipefail", "-c"]

COPY requirements.txt /opt/pais/gpu-requirements.txt
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv pip install --system --break-system-packages --no-cache --python /usr/local/bin/python \
      -r /opt/pais/gpu-requirements.txt \
 && /usr/local/bin/python -c 'import torch, torchvision, torchaudio, numpy, scipy, pandas, sklearn, matplotlib, transformers, accelerate, datasets, safetensors; print("torch", torch.__version__, "cuda", torch.version.cuda)'

# A JupyterLab kernel for it. JupyterLab runs from its own uv tool environment, whose default kernel
# doesn't see these packages; this one runs the default Python. /usr/local/share/jupyter is on
# Jupyter's data path.
RUN /usr/local/bin/python -m ipykernel install --prefix /usr/local --name pais-gpu \
      --display-name 'Python 3 (GPU: PyTorch)' \
 && test -f /usr/local/share/jupyter/kernels/pais-gpu/kernel.json

# As pais-base ends.
ENV BASH_ENV=/etc/pais/env.sh
USER nobody
