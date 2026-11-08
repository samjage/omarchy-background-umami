# shellcheck shell=bash
# Run a command under a memory cap and a wall-clock limit, without crash reports.
#
# A plain `ulimit -v` stops a memory bomb by making the program abort. That is a
# SIGABRT, so the system writes a core dump and Omarchy pops up "Process
# crashed" for every hostile image. This watches the program's memory instead and
# stops it with SIGKILL, which leaves no crash report. `ulimit -v` stays as a
# high backstop (four times the cap) in case memory grows faster than we poll.
#
# umami_run_limited <memory cap in KB> <seconds> <command> [args...]
# Returns the command's status, or 137 if it was stopped. Redirect output at the call.
umami_run_limited() {
  local cap_kb=$1 seconds=$2 pid rss start=$SECONDS status
  shift 2
  ( ulimit -v "$((cap_kb * 4))" 2>/dev/null || exit 125; exec "$@" ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
    if { [[ -n $rss ]] && ((rss > cap_kb)); } || ((SECONDS - start >= seconds)); then
      kill -KILL "$pid" 2>/dev/null
      break
    fi
    sleep 0.02
  done
  wait "$pid" 2>/dev/null
  status=$?
  return "$status"
}
