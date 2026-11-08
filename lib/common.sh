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
# Text that may contain a file name is shown as plain, bounded text: control
# characters (terminal escape sequences, newlines) become "?" and it is cut at
# 300 characters, so a hostile name cannot repaint the terminal or flood a toast.
# Thumbnails of files that changed or went away would pile up forever. Drop the
# ones not used for 30 days, and keep at most 4000 (about 400 MB), oldest first.
# umami-pick touches the thumbnails it shows, so those in use stay.
umami_prune_thumbs() {
  local dir="$UMAMI_CACHE/thumbs" f
  [[ -d $dir ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.jpg' -mtime +30 -delete 2>/dev/null
  while IFS= read -r f; do rm -f -- "$f"; done < <(
    find "$dir" -maxdepth 1 -type f -name '*.jpg' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +4001 | cut -d' ' -f2-)
  return 0
}

umami_plain() { local t=${*//[[:cntrl:]]/?}; printf '%s' "${t:0:300}"; }
umami_notify() { omarchy-notification-send "$(umami_plain "$1")" -t 3000 2>/dev/null || true; }

# Report a problem where the user will see it: the terminal, or a notification
# when we were started from a menu row.
umami_die() {
  echo "umami: $(umami_plain "$*")" >&2
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

# ---- applying a wallpaper ----------------------------------------------------
# Every wallpaper we set goes through umami_apply, and nothing else in this
# plugin calls omarchy-theme-bg-set on a file from a folder. The shell decodes
# whatever it is given, with no limit, so a crafted image must never reach it.
# umami_apply copies the file into a private folder (mode 700, so nobody can
# swap it afterwards), runs the memory/CPU-limited thumbnail worker on the COPY,
# and only then sets the copy. A file that fails is not applied. Checking the
# copy rather than remembering a past check means there is no cache to forge and
# no gap between checking and using.
UMAMI_APPLIED="$UMAMI_CACHE/applied"
# A file in the applied folder is trusted only if its folder carries this marker,
# written after the clean step succeeded. Folders made by older versions held
# original image bytes and have no marker, so they are never trusted.
UMAMI_CLEAN_MARK=".clean-v1"

umami_is_clean_copy() { [[ -f $1 && -f $(dirname -- "$1")/$UMAMI_CLEAN_MARK ]]; }

# Remove everything in the applied folder that is not a marked clean copy, except
# the file now showing (deleting it would leave the wallpaper link dangling; it is
# re-cleaned before it can ever be applied again).
umami_applied_migrate() {
  local root dir current
  root=$(umami_applied_root)
  [[ -d $root ]] || return 0
  current=$(dirname -- "$(umami_current_background)")
  while IFS= read -r -d '' dir; do
    [[ -f $dir/$UMAMI_CLEAN_MARK || $dir == "$current" ]] || rm -rf -- "$dir"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  find "$root" -mindepth 1 -maxdepth 1 ! -type d -delete 2>/dev/null
  return 0
}

umami_applied_root() { readlink -f -- "$UMAMI_APPLIED" 2>/dev/null || printf '%s' "$UMAMI_APPLIED"; }

# Keep the newest few copies (the previous wallpaper must survive a "Nevermind")
# and whichever one is showing.
umami_applied_prune() {
  local root dir current n=0
  root=$(umami_applied_root)
  current=$(dirname -- "$(umami_current_background)")
  while IFS= read -r dir; do
    n=$((n + 1))
    ((n > 3)) && [[ $dir != "$current" ]] && rm -rf -- "$dir"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
  return 0
}

# umami_apply <plugin root> <image>: set it as the wallpaper if it is safe to.
# Prints the path that was set. Returns non-zero (and sets nothing) otherwise.
#
# What is set is never the original file. The shell decodes with Qt, which reads
# parts of an image (PNG text chunks after the pixel data, for one) that the
# libvips check never touches, so passing the check proves nothing about Qt. So:
# copy the file into the private folder (a hard byte cap, so nobody can swap it
# or grow it), decode it with libvips under memory/CPU limits, write a fresh
# clean image holding only the pixels (umami-clean), delete the copy, and set the
# clean image. If any step fails, nothing is set.
umami_apply() {
  local root=$1 real dir applied size max name stem ext clean
  mkdir -p "$UMAMI_APPLIED" && chmod 700 "$UMAMI_APPLIED" || return 1
  applied=$(umami_applied_root)
  real=$(readlink -f -- "$2" 2>/dev/null) || return 1
  if [[ $real == "$applied"/* ]] && umami_is_clean_copy "$real"; then # one of our own, marked clean images
    omarchy-theme-bg-set "$real" || return 1
    printf '%s' "$real"
    return 0
  fi
  [[ -f $real ]] || return 1
  max=${UMAMI_THUMB_MAX_BYTES:-268435456}
  size=$(stat -c %s -- "$real" 2>/dev/null) || return 1
  ((size <= max)) || return 1
  dir=$(mktemp -d "$applied/XXXXXXXX") || return 1
  name=${real##*/}; stem=${name%.*}; ext=${name##*.}
  [[ $name == *.* ]] || { stem=$name; ext=img; }
  case ${ext,,} in jpg | jpeg) clean="$dir/$stem.jpg" ;; *) clean="$dir/$stem.png" ;; esac
  if ! { timeout 30 head -c "$((max + 1))" -- "$real" >"$dir/source.$ext" &&
    (($(stat -c %s -- "$dir/source.$ext") <= max)) &&
    printf '%s\n' "$real" >"$dir/origin" &&
    "$root/libexec/umami-clean" "$dir/source.$ext" "$clean" &&
    [[ -s $clean ]] &&
    : >"$dir/$UMAMI_CLEAN_MARK"; } 2>/dev/null; then
    rm -rf -- "$dir"
    return 1
  fi
  rm -f -- "$dir/source.$ext"
  omarchy-theme-bg-set "$clean" || { rm -rf -- "$dir"; return 1; }
  umami_applied_migrate
  umami_applied_prune
  printf '%s' "$clean"
}

# The file a wallpaper was made from: for one of our copies, the original path;
# otherwise the wallpaper itself. Use this wherever the current wallpaper is
# compared with a picked or pinned file.
umami_current_origin() {
  local current origin
  current=$(umami_current_background)
  if [[ $current == "$(umami_applied_root)"/* ]]; then
    origin=$(head -n1 -- "$(dirname -- "$current")/origin" 2>/dev/null)
    [[ -n $origin ]] && current=$(readlink -f -- "$origin" 2>/dev/null || printf '%s' "$origin")
  fi
  printf '%s' "$current"
}
