#!/usr/bin/env bash
# nfs-server: starts the node kernel's NFS server from this container, serves the exports in /etc/exports.d, and
# stops the server when the container stops. The container must be privileged: it mounts the nfsd and rpc_pipefs
# filesystems (which loads the node's nfsd module) and starts kernel nfsd threads in the pod's network namespace.
#
#   nfs-server run     start, log the exports, then wait; TERM or INT stops the server
#   nfs-server check   exit 0 if the server is up (for the liveness and readiness probes)
#
# Settings (environment):
#   NFS_VERSIONS       versions to serve, space-separated, from: 3 4.0 4.1 4.2 (default "4.1 4.2")
#   NFS_THREADS        nfsd threads (default 8)
#   NFS_STATE_DIR      stable storage, on the persistent volume: NFSv4 client records (nfsdcld) and NFSv3 statd
#                      state, so clients can reclaim locks after a restart (default /srv/state)
#   NFS_EXPORT_DIRS    directories to create (root:root 0755) before exporting, space-separated (default none)
#   NFS_GRACE_TIME     seconds (default 90)
#   NFS_LEASE_TIME     seconds (default 90)
#   MOUNTD_PORT, STATD_PORT, STATD_OUTGOING_PORT, LOCKD_PORT
#                      fixed ports, used only with NFSv3 (defaults 20048, 32765, 32766, 32803)
#
# Exports: one or more files named *.exports in /etc/exports.d (exports(5) syntax), e.g. a mounted ConfigMap.
set -euo pipefail

NFS_VERSIONS="${NFS_VERSIONS:-4.1 4.2}"
NFS_THREADS="${NFS_THREADS:-8}"
NFS_STATE_DIR="${NFS_STATE_DIR:-/srv/state}"
NFS_EXPORT_DIRS="${NFS_EXPORT_DIRS:-}"
NFS_GRACE_TIME="${NFS_GRACE_TIME:-90}"
NFS_LEASE_TIME="${NFS_LEASE_TIME:-90}"
MOUNTD_PORT="${MOUNTD_PORT:-20048}"
STATD_PORT="${STATD_PORT:-32765}"
STATD_OUTGOING_PORT="${STATD_OUTGOING_PORT:-32766}"
LOCKD_PORT="${LOCKD_PORT:-32803}"

PIPEFS=/var/lib/nfs/rpc_pipefs
pids=()

log() { printf '%s nfs-server: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "error: $*"; exit 1; }

serves() { [[ " ${NFS_VERSIONS} " == *" $1 "* ]]; }
serves_v4() { serves 4.0 || serves 4.1 || serves 4.2; }
yn() { if "$@"; then echo y; else echo n; fi; }

# A process of this name is running in the container.
running() {
    local comm
    for comm in /proc/[0-9]*/comm; do
        [ "$(cat "${comm}" 2>/dev/null)" = "$1" ] && return 0
    done
    return 1
}

check_settings() {
    local v
    for v in ${NFS_VERSIONS}; do
        case "${v}" in
            3 | 4.0 | 4.1 | 4.2) ;;
            *) die "NFS_VERSIONS: unknown version '${v}' (use 3, 4.0, 4.1 or 4.2)" ;;
        esac
    done
    [ -n "${NFS_VERSIONS// /}" ] || die "NFS_VERSIONS is empty"
    compgen -G '/etc/exports.d/*.exports' > /dev/null \
        || die "no exports: mount one or more files named *.exports at /etc/exports.d"
}

# The whole of /etc/nfs.conf, so nothing from the package's default file applies by accident.
write_conf() {
    cat > /etc/nfs.conf << EOF
# Written by nfs-server at start (images/nfs-server/entrypoint.sh in drai-inn/pais-images).
[nfsd]
threads=${NFS_THREADS}
grace-time=${NFS_GRACE_TIME}
lease-time=${NFS_LEASE_TIME}
tcp=y
udp=n
vers3=$(yn serves 3)
vers4=$(yn serves_v4)
vers4.0=$(yn serves 4.0)
vers4.1=$(yn serves 4.1)
vers4.2=$(yn serves 4.2)

[mountd]
port=${MOUNTD_PORT}

[nfsdcld]
storagedir=${NFS_STATE_DIR}/nfsdcld

[statd]
port=${STATD_PORT}
outgoing-port=${STATD_OUTGOING_PORT}
state-directory-path=${NFS_STATE_DIR}/statd

[lockd]
port=${LOCKD_PORT}
udp-port=${LOCKD_PORT}
EOF
}

start() {
    local d
    check_settings
    mkdir -p "${NFS_STATE_DIR}/nfsdcld" "${NFS_STATE_DIR}/statd" "${PIPEFS}"
    for d in ${NFS_EXPORT_DIRS}; do
        [ -d "${d}" ] || install -d -o root -g root -m 0755 "${d}"
    done
    write_conf

    mountpoint -q /proc/fs/nfsd || mount -t nfsd nfsd /proc/fs/nfsd \
        || die "can't mount the nfsd filesystem: the node kernel needs the nfsd module, and this container must be privileged"
    mountpoint -q "${PIPEFS}" || mount -t rpc_pipefs sunrpc "${PIPEFS}" \
        || die "can't mount rpc_pipefs at ${PIPEFS}"

    if serves 3; then
        rpcbind -f -w &
        pids+=("$!")
        rpc.statd -F &
        pids+=("$!")
    fi
    if serves_v4; then
        # Before nfsd starts, so the kernel finds the client-tracking pipe.
        nfsdcld -F &
        pids+=("$!")
    fi

    exportfs -ra || die "exportfs failed: check the files in /etc/exports.d"

    local mountd_args=(-F -N 2)
    serves 3 || mountd_args+=(-N 3)
    rpc.mountd "${mountd_args[@]}" &
    pids+=("$!")

    rpc.nfsd "${NFS_THREADS}" || die "rpc.nfsd failed to start the kernel server"
    if serves 3; then
        sm-notify || log "sm-notify failed: NFSv3 clients won't be told to reclaim their locks"
    fi

    log "serving NFS ${NFS_VERSIONS} over TCP with ${NFS_THREADS} threads"
    exportfs -v | while IFS= read -r line; do log "export: ${line}"; done
}

stop() {
    local rc="${1:-0}"
    trap - TERM INT
    log "stopping"
    exportfs -ua || log "exportfs -ua failed"
    rpc.nfsd 0 || log "rpc.nfsd 0 failed"
    for pid in "${pids[@]}"; do kill "${pid}" 2> /dev/null || true; done
    wait || true
    umount "${PIPEFS}" 2> /dev/null || true
    umount /proc/fs/nfsd 2> /dev/null || true
    log "stopped"
    exit "${rc}"
}

check() {
    local threads
    threads="$(cat /proc/fs/nfsd/threads 2> /dev/null || echo 0)"
    [ "${threads}" -gt 0 ] || { echo "nfsd has no threads"; exit 1; }
    running rpc.mountd || { echo "rpc.mountd isn't running"; exit 1; }
    if serves_v4; then running nfsdcld || { echo "nfsdcld isn't running"; exit 1; }; fi
    if serves 3; then
        running rpcbind || { echo "rpcbind isn't running"; exit 1; }
        running rpc.statd || { echo "rpc.statd isn't running"; exit 1; }
    fi
    echo "ok: ${threads} nfsd threads"
}

case "${1:-run}" in
    run)
        trap 'stop 0' TERM INT
        start
        # A helper that exits takes the server down with it, so the container restarts cleanly.
        rc=0
        wait -n "${pids[@]}" || rc=$?
        log "a helper process exited (status ${rc})"
        stop 1
        ;;
    check) check ;;
    *) die "usage: nfs-server run|check" ;;
esac
