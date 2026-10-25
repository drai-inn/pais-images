# nfs-server: configures and runs the Linux kernel's NFS server (nfsd) from a container. The server itself is the
# node kernel's: this image holds only the user-space side (rpc.nfsd, rpc.mountd, exportfs, nfsdcld, and rpcbind and
# rpc.statd for NFSv3), so the pod running it must be privileged. Built for ai-gpu-test's workspace homes
# (drai-inn/ai-gpu-deployment, clusters/ai-gpu-test/workspaces-home/); production homes are on VAST.
#
# Public kernel-NFS images are unmaintained (itsthenetwork/nfs-server-alpine last tagged 2019, erichough/nfs-server
# 2020), so this one is ours: Ubuntu's own nfs-kernel-server, pinned to the version in VERSION. A new Ubuntu package
# version is a new image version.

ARG UBUNTU_TAG=noble-20260917

FROM ubuntu:${UBUNTU_TAG}
ARG NFS_UTILS_VERSION
RUN test -n "${NFS_UTILS_VERSION}" || { echo "NFS_UTILS_VERSION build arg is required" >&2; exit 1; }

# util-linux (mount, mountpoint) is in the base image. nfs-kernel-server's postinst can't start services in a build.
# /etc/exports stays, empty: exportfs won't run without it. The exports themselves go in /etc/exports.d.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        "nfs-kernel-server=1:${NFS_UTILS_VERSION}" \
        "nfs-common=1:${NFS_UTILS_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    && : > /etc/exports \
    && mkdir -p /etc/exports.d

COPY entrypoint.sh /usr/local/bin/nfs-server
RUN chmod 0755 /usr/local/bin/nfs-server

LABEL org.opencontainers.image.title="nfs-server" \
      org.opencontainers.image.version="${NFS_UTILS_VERSION}" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.description="Runs the node kernel's NFS server (nfsd) from a privileged pod; Ubuntu nfs-kernel-server ${NFS_UTILS_VERSION}"

EXPOSE 2049/tcp
ENTRYPOINT ["/usr/local/bin/nfs-server"]
CMD ["run"]
