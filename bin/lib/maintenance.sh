#!/usr/bin/env bash
# Shared by mac-update and mac-cleanup; compatible with macOS bash 3.2.
#
# Callers set JOB (a short name, e.g. "update") before sourcing, then use:
#   parse_args "$@"     sets DRY, FORCE
#   log_header          dated line at the top of each launchd run
#   gates_ok            power and interval gates (skipped by --force/--dry-run)
#   acquire_lock        one maintenance job at a time
#   busy_exit <reason>  leave when a build is running

STATE_DIR="$HOME/.local/state"
STAMP="$STATE_DIR/mac-$JOB.last"
INTERVAL=$((6 * 86400 + 43200))   # 6.5 days, leaves room for daily jitter

# Runs on AC, or on battery above BATTERY_MIN percent. The point of the gate is
# not to spend a long unplugged session on background work; a nearly full
# battery is no reason to skip.
BATTERY_MIN="${BATTERY_MIN:-65}"

mkdir -p "$STATE_DIR"

# Started by hand in a terminal (launchd gives us /dev/null and a log file).
INTERACTIVE=0
if [ -t 0 ] && [ -t 1 ]; then INTERACTIVE=1; fi

# Colours only on a terminal, so the launchd logs stay plain text.
if [ -t 1 ]; then
  C_B=$'\033[1m' C_OK=$'\033[32m' C_SK=$'\033[33m' C_ERR=$'\033[31m' C_0=$'\033[0m'
else
  C_B='' C_OK='' C_SK='' C_ERR='' C_0=''
fi
b()   { printf '\n%s> %s%s\n' "$C_B" "$1" "$C_0"; }
ok()  { printf '%s  + %s%s\n' "$C_OK" "$1" "$C_0"; }
sk()  { printf '%s  - %s%s\n' "$C_SK" "$1" "$C_0"; }
err() { printf '%s  ! %s%s\n' "$C_ERR" "$1" "$C_0" >&2; }

DRY=0
FORCE=0
parse_args() {
  local a
  for a in "$@"; do
    case "$a" in
      --dry-run|-n) DRY=1 ;;
      --force|-f)   FORCE=1 ;;
      *) printf 'Unknown argument: %s\n' "$a" >&2; exit 2 ;;
    esac
  done
}

# launchd appends to the log forever. Past LOG_MAX_KB keep the newest quarter,
# rewriting in place: launchd holds this same file open in append mode.
LOG_MAX_KB=1024
trim_log() {
  local log="$HOME/Library/Logs/dotfiles/$JOB.log" tmp
  [ -f "$log" ] || return 0
  [ "$(du -k "$log" | awk '{print $1}')" -gt "$LOG_MAX_KB" ] || return 0
  tmp=$(mktemp "$STATE_DIR/mac-$JOB.log.XXXXXX") || return 0
  # Drop the first, probably cut, line of the kept tail.
  if tail -c $((LOG_MAX_KB * 256)) "$log" | sed 1d > "$tmp"; then cat "$tmp" > "$log"; fi
  rm -f "$tmp"
}

log_header() {
  [ "$INTERACTIVE" -eq 1 ] && return 0
  trim_log
  printf '\n=== %s  mac-%s%s%s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$JOB" \
    "$([ "$FORCE" -eq 1 ] && echo ' --force')" "$([ "$DRY" -eq 1 ] && echo ' --dry-run')"
}

power_ok() {
  pmset -g ps | grep -q 'AC Power' && return 0
  BATTERY_PCT=$(pmset -g batt | grep -Eo '[0-9]{1,3}%' | head -1 | tr -d '%')
  [ -n "$BATTERY_PCT" ] && [ "$BATTERY_PCT" -gt "$BATTERY_MIN" ]
}

gates_ok() {
  if [ "$FORCE" -eq 1 ] || [ "$DRY" -eq 1 ]; then return 0; fi
  if ! power_ok; then
    printf 'On battery at %s%% (need >%s%%) — skipping, will retry tomorrow.\n' \
      "${BATTERY_PCT:-?}" "$BATTERY_MIN"
    return 1
  fi
  if [ -f "$STAMP" ]; then
    local elapsed=$(( $(date +%s) - $(stat -f %m "$STAMP") ))
    if [ "$elapsed" -lt "$INTERVAL" ]; then
      printf 'Last %s %d days ago — too soon.\n' "$JOB" $((elapsed / 86400))
      return 1
    fi
  fi
  return 0
}

# One lock for both jobs: they both drive brew, and cleanup must not delete
# what update is downloading. The lock is a symlink whose target is the owner's
# PID — creating it is atomic, and a dead owner's lock is taken over.
LOCK="$STATE_DIR/mac-maintenance.lock"
acquire_lock() {
  local owner
  if ln -s "$$" "$LOCK" 2>/dev/null; then
    trap 'rm -f "$LOCK"' EXIT
    return 0
  fi
  owner=$(readlink "$LOCK" 2>/dev/null)
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    printf 'Another maintenance job is running (pid %s, %s) — not starting.\n' \
      "$owner" "$(ps -o command= -p "$owner" 2>/dev/null |
        awk '{for (i = 1; i <= NF; i++) if ($i ~ /mac-/) { n = split($i, p, "/"); print p[n]; exit }}')"
    return 1
  fi
  rm -f "$LOCK"
  if ln -s "$$" "$LOCK" 2>/dev/null; then
    trap 'rm -f "$LOCK"' EXIT
    return 0
  fi
  echo "Could not take the maintenance lock — not starting." >&2
  return 1
}

busy_exit() { # busy_exit <what is running>
  if [ "$FORCE" -eq 1 ]; then
    printf '%s — not starting. Run it again once that finishes.\n' "$1"
  else
    printf '%s — touching nothing. Back tomorrow.\n' "$1"
  fi
  exit 0
}

build_running() {
  # Build clients, rather than the long-lived Flutter/Gradle idle daemons.
  pgrep -f 'flutter_tools.snapshot.*(build|run|test)|flutter_tester|GradleWrapperMain|org.gradle.launcher.GradleMain' >/dev/null 2>&1 && return 0
  pgrep -f 'GradleDaemon' >/dev/null 2>&1 || return 1

  # IDE builds may use the daemon directly. Ask installed distributions for
  # their status without fetching a wrapper or starting a build.
  local gradle status saw_idle=0 java_home="${JAVA_HOME:-}"
  if [ -d '/Applications/Android Studio.app/Contents/jbr/Contents/Home' ]; then
    java_home='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
  fi
  while IFS= read -r -d '' gradle; do
    if ! status=$(JAVA_HOME="$java_home" "$gradle" --offline --console=plain --status 2>&1); then
      echo "Cannot determine Gradle daemon status; skipping maintenance." >&2
      return 0
    fi
    if printf '%s\n' "$status" | grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+BUSY'; then return 0; fi
    if printf '%s\n' "$status" | grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+IDLE'; then saw_idle=1; fi
  done < <(find "$HOME/.gradle/wrapper/dists" -type f -path '*/bin/gradle' -print0 2>/dev/null)
  if [ "$saw_idle" -eq 1 ]; then return 1; fi
  echo "Gradle daemon found without a readable status; skipping maintenance." >&2
  return 0
}
