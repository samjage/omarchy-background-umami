# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# Shared paths and helpers for Background Umami. Sourced, never run.

UMAMI_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-background-umami"
UMAMI_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-background-umami"
UMAMI_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-background-umami"
OMARCHY_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
OMARCHY_USER="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"

# Omarchy keeps stock themes in /usr/share and git-installed ones under ~/.config.
UMAMI_THEME_ROOTS=("${OMARCHY_PATH:-/usr/share/omarchy}/themes" "$OMARCHY_USER/themes")

# Same formats as omarchy-theme-bg-next.
UMAMI_IMAGES=(\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \))

# Limits that keep a mistaken custom folder from swamping the picker.
UMAMI_MAX_DEPTH=4
UMAMI_MAX_IMAGES=2000

# Never end a pipeline with `grep -q` here: it quits at the first match, the
# command feeding it dies of SIGPIPE, and pipefail then reports the whole
# pipeline as failed. Capture the output first, then test it.

umami_current_theme() { cat "$OMARCHY_STATE/current/theme.name" 2>/dev/null; }
umami_current_background() { readlink -f "$OMARCHY_STATE/current/background" 2>/dev/null; }

# The cache holds copies of your pictures (thumbnails), so only you may open it.
# Tightens a cache made by an earlier version too.
umami_private_cache() {
  mkdir -p "$UMAMI_CACHE/thumbs" && chmod 700 "$UMAMI_CACHE" "$UMAMI_CACHE/thumbs"
}
umami_notify() { omarchy-notification-send "$1" -t 3000 2>/dev/null || true; }

# Report a problem where the user will see it: the terminal, or a notification
# when we were started from a menu row.
umami_die() {
  echo "umami: $*" >&2
  [[ -t 2 ]] || umami_notify "Umami: $*"
  exit 1
}

# A path as people write it: the home folder shortened to ~. Only paths inside
# the home folder change, so /home/alexa is not mistaken for /home/alex.
umami_tilde() {
  # shellcheck disable=SC2088  # a literal ~ is exactly what we mean to print
  case $1 in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

umami_has_images() { [[ -n $(find -L "$1" -maxdepth 2 -type f "${UMAMI_IMAGES[@]}" -print -quit 2>/dev/null) ]]; }

umami_pictures_folder() {
  local pictures
  pictures=$(xdg-user-dir PICTURES 2>/dev/null)
  [[ -n $pictures && $pictures != "$HOME" ]] || pictures="$HOME/Pictures"
  printf '%s' "$pictures"
}

# Folders in Pictures a person plausibly keeps wallpapers in: Backgrounds,
# Wallpapers or Wallpaper, in any capitalization, one per line.
umami_folder_candidates() {
  local name
  for name in backgrounds wallpapers wallpaper; do
    find "$(umami_pictures_folder)" -mindepth 1 -maxdepth 1 -type d -iname "$name" 2>/dev/null | sort
  done
}

# Where wallpapers go unless told otherwise. A folder the user already keeps
# them in wins, preferring one that has images in it. Only when there is none
# do we pick a new Backgrounds, named like Omarchy's own folder.
umami_default_folder() {
  local dir first=""
  while IFS= read -r dir; do
    [[ -n $first ]] || first=$dir
    if umami_has_images "$dir"; then printf '%s' "$dir"; return; fi
  done < <(umami_folder_candidates)
  printf '%s' "${first:-$(umami_pictures_folder)/Backgrounds}"
}

# Width for a prompt. Omarchy's menu is 300 wide and cuts anything longer than
# about 20 characters, so give it room for the longest line given.
umami_menu_width() {
  local longest=0 line width
  for line in "$@"; do
    ((${#line} > longest)) && longest=${#line}
  done
  width=$((13 * (longest + 8)))
  ((width < 300)) && width=300
  ((width > 900)) && width=900
  printf '%s' "$width"
}

# A custom folder must be a real directory, and never / or the home folder.
umami_safe_folder() {
  local dir
  dir=$(readlink -f -- "$1" 2>/dev/null) || return 1
  [[ -d $dir && $dir != / && $dir != "$(readlink -f "$HOME")" ]]
}

# Folders chosen at install, one per line in $UMAMI_CONFIG/folders. Unsafe ones
# are skipped. With no config, the default folder.
umami_custom_folders() {
  local file="$UMAMI_CONFIG/folders" line
  if [[ ! -s $file ]]; then
    umami_default_folder
    printf '\n'
    return
  fi
  while IFS= read -r line; do
    line=${line/#\~/$HOME}
    [[ -n $line && $line != \#* ]] && umami_safe_folder "$line" && printf '%s\n' "$line"
  done <"$file"
}
