# pais-base: python-base plus nss_wrapper, for Workspaces that run as the person's FreeIPA uid.
#
# The pod's uid has no entry in the image's /etc/passwd, so `whoami` fails and shells print "I have no name!". The
# workspace bootstrap (ai-gpu-deployment, coder-oss/workspace-template/pais-base/coder_bootstrap.py) writes a copy of
# passwd and group in /tmp with the owner and pais-users added, and preloads this library to read them. It is a stopgap:
# only the owner and pais-users get names, so project groups stay numeric until WP4's pod-facing SSSD replaces it.
#
# Layered on a pinned digest rather than added to python-base: production pins python-base, and a rebuild moves conda,
# uv and JupyterLab with it. To move: change this digest and bump VERSION (the image tag) in the same commit.
FROM ghcr.io/drai-inn/pais-images/python-base@sha256:b1292af59622466567fc596f09f49dd003a3823ccbd504f97a48bc53687c8454

USER root

RUN apt-get update \
 && apt-get install --yes --no-install-recommends libnss-wrapper \
 && rm -rf /var/lib/apt/lists/*

# Fail the build if the library isn't where the bootstrap looks, or doesn't resolve a name on this image's glibc.
RUN set -eu; \
    lib=/usr/lib/x86_64-linux-gnu/libnss_wrapper.so; \
    d=$(mktemp -d); \
    cp /etc/passwd /etc/group "$d"; \
    echo 'probe:x:14000:20001:probe:/tmp:/bin/bash' >> "$d/passwd"; \
    test "$(LD_PRELOAD=$lib NSS_WRAPPER_PASSWD=$d/passwd NSS_WRAPPER_GROUP=$d/group getent passwd 14000 | cut -d: -f1)" = probe; \
    rm -rf "$d"

USER nobody
