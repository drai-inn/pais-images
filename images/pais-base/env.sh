# /etc/pais/env.sh: settings that depend on the Workspace, for every way into it.
#
# Sourced by interactive bash (/etc/bash.bashrc), non-interactive bash (BASH_ENV) and the start-up,
# which runs under sh, so this is POSIX sh. Values already set win: a researcher can export their
# own, and a shell started from one that ran this keeps what it inherited.

# Thread pools sized to the CPU limit. The container sees every core on the node through
# sched_getaffinity while the cgroup holds it to its limit, and OpenMP/BLAS size their pools off the
# affinity mask, so an unset default spawns one thread per node core on a 2-core quota.
# PYTHON_CPU_COUNT makes os.cpu_count() report the limit (Python >= 3.13), so multiprocessing.Pool()
# and ProcessPoolExecutor() stop defaulting to one process per node core. Never OMP_PROC_BIND or
# OMP_PLACES: with no cpuset every Workspace would bind to the same first cores.
if read -r q p 2>/dev/null </sys/fs/cgroup/cpu.max && [ "$q" != max ]; then
  n=$(( (q + p - 1) / p ))
  : "${OMP_NUM_THREADS:=$n}" "${OPENBLAS_NUM_THREADS:=$n}" "${MKL_NUM_THREADS:=$n}" \
    "${NUMEXPR_MAX_THREADS:=$n}" "${NUMEXPR_NUM_THREADS:=$n}" "${NUMBA_NUM_THREADS:=$n}" \
    "${POLARS_MAX_THREADS:=$n}" "${OPENCV_FOR_THREADS_NUM:=$n}" "${PYTHON_CPU_COUNT:=$n}"
  export OMP_NUM_THREADS OPENBLAS_NUM_THREADS MKL_NUM_THREADS NUMEXPR_MAX_THREADS NUMEXPR_NUM_THREADS \
    NUMBA_NUM_THREADS POLARS_MAX_THREADS OPENCV_FOR_THREADS_NUM PYTHON_CPU_COUNT
  unset n
fi
unset q p

# uv tools, `uv python install --default` and `npm -g` (via /usr/local/etc/npmrc) land in
# ~/.local/bin; first on PATH so the researcher's own copies win over the image's.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

# The uid has no entry in the image's passwd; the start-up's nss_wrapper files give it a name.
# The template sets these three for the container, but a way in that builds its own environment
# doesn't pass them on: Tailscale SSH (PAIS Connect) starts each session with only USER, HOME, SHELL,
# PATH, TERM/LANG/LC_* and SSH_*, so `id` showed numbers and bash "I have no name!". Set them here
# whenever the start-up's files exist; values already set win.
if [ -r /tmp/pais-nss/passwd ] && [ -r /tmp/pais-nss/group ]; then
  : "${NSS_WRAPPER_PASSWD:=/tmp/pais-nss/passwd}" "${NSS_WRAPPER_GROUP:=/tmp/pais-nss/group}"
  export NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
  case " ${LD_PRELOAD:-} " in
    *libnss_wrapper.so*) ;;
    *) LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libnss_wrapper.so${LD_PRELOAD:+ $LD_PRELOAD}"; export LD_PRELOAD ;;
  esac
fi
[ -n "${USER:-}" ] || USER=$(id -un 2>/dev/null) && export USER
: "${LOGNAME:=$USER}" && export LOGNAME

# bash resolves \u in its prompt when it starts, before this file sets LD_PRELOAD, so a shell started
# without nss_wrapper loaded (a Tailscale SSH session) shows "I have no name!" although `id` works.
# Interactive bash only: \u in the prompt becomes the name in USER. A prompt set later (~/.bashrc) wins.
case "${BASH_VERSION:-}:$-" in
  ?*:*i*)
    case "${PS1:-}:${USER:-}" in
      *'\u'*:?*) PS1=$(printf '%s' "$PS1" | sed "s/\\\\u/$USER/g") ;;
    esac ;;
esac

# opencode keeps its state in one SQLite database opened in WAL mode, and WAL cannot be shared
# across nodes over NFS: two Workspaces using the default ~/.local/share/opencode/opencode.db fail
# with "locking protocol". One database per Workspace, still in the home so it survives restarts.
# A bare file name resolves inside opencode's data dir.
[ -z "${RUNAI_JOB_NAME:-}" ] || : "${OPENCODE_DB:=opencode-${RUNAI_PROJECT:-}-$RUNAI_JOB_NAME.db}"
[ -z "${OPENCODE_DB:-}" ] || export OPENCODE_DB

# The soft stack limit is 8 MiB and the hard limit unlimited: raise it for deep recursion in
# numerical code. It covers this process's main thread and its children; OpenMP workers take
# OMP_STACKSIZE.
ulimit -s unlimited 2>/dev/null || true
