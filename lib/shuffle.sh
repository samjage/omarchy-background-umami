# shellcheck shell=bash
# shellcheck disable=SC2034  # UMAMI_PRESETS is used by the scripts that source this file
# The shuffle timer: two small systemd user units that we generate and own.
# They exist only while shuffle is on, so nothing is left behind when it is off.

UMAMI_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UMAMI_UNIT_MARK='# umami-background-shuffle'
UMAMI_PRESETS=(5 15 30 60)

# Quote a path for an ExecStart= line (spaces, quotes, backslashes, % specifiers).
umami_unit_quote() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//%/%%}
  printf '"%s"' "$s"
}

umami_unit_is_ours() { [[ ! -e $1 ]] || grep -qF "$UMAMI_UNIT_MARK" "$1"; }

umami_shuffle_units_write() { # <plugin root> <minutes>
  local service="$UMAMI_UNIT_DIR/umami-shuffle.service" timer="$UMAMI_UNIT_DIR/umami-shuffle.timer"
  if ! umami_unit_is_ours "$service" || ! umami_unit_is_ours "$timer"; then
    umami_die "$UMAMI_UNIT_DIR already has umami-shuffle units that are not ours."
  fi
  mkdir -p "$UMAMI_UNIT_DIR"
  {
    printf '%s\n[Unit]\nDescription=Background Umami: pick the next wallpaper\n\n' "$UMAMI_UNIT_MARK"
    printf '[Service]\nType=oneshot\nExecStart=%s tick\n' "$(umami_unit_quote "$1/libexec/umami-shuffle")"
  } >"$service"
  {
    printf '%s\n[Unit]\nDescription=Background Umami: shuffle timer\n\n' "$UMAMI_UNIT_MARK"
    printf '[Timer]\nOnActiveSec=%smin\nOnUnitActiveSec=%smin\nAccuracySec=1s\n\n' "$2" "$2"
    printf '[Install]\nWantedBy=timers.target\n'
  } >"$timer"
}

# Stop the timer and delete our units. Safe to call when there is nothing to do.
umami_shuffle_units_remove() {
  local file found=false
  for file in "$UMAMI_UNIT_DIR/umami-shuffle.timer" "$UMAMI_UNIT_DIR/umami-shuffle.service"; do
    [[ -f $file ]] || continue
    grep -qF "$UMAMI_UNIT_MARK" "$file" || continue
    found=true
    [[ $file == *.timer ]] && systemctl --user disable --now umami-shuffle.timer >/dev/null 2>&1
    rm -f -- "$file"
  done
  if $found; then systemctl --user daemon-reload >/dev/null 2>&1; fi
  return 0
}
