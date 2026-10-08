# shellcheck shell=bash
# The theme-set hook that keeps a pinned wallpaper through theme changes.
# Omarchy runs every file in hooks/theme-set.d/ as: bash <file> <theme>.
# Ours is a three-line stub, so removing the plugin leaves a harmless no-op.

UMAMI_HOOK="$OMARCHY_USER/hooks/theme-set.d/50-umami-pin"
UMAMI_HOOK_MARK='# umami-background-hook'

umami_hook_install() { # <plugin root>
  local target="$1/libexec/umami-pin-apply"
  mkdir -p "$(dirname "$UMAMI_HOOK")"
  if [[ -e $UMAMI_HOOK ]] && ! grep -qF "$UMAMI_HOOK_MARK" "$UMAMI_HOOK"; then
    umami_die "$UMAMI_HOOK exists and is not ours."
  fi
  {
    printf '#!/bin/bash\n%s\n' "$UMAMI_HOOK_MARK"
    printf 'if [[ -x %q ]]; then exec %q "$@"; fi\n' "$target" "$target"
  } >"$UMAMI_HOOK"
}

umami_hook_uninstall() {
  [[ -f $UMAMI_HOOK ]] && grep -qF "$UMAMI_HOOK_MARK" "$UMAMI_HOOK" && rm -f -- "$UMAMI_HOOK"
  return 0
}
