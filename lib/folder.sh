# shellcheck shell=bash
# Choosing the folder that holds the user's own wallpapers.

# Say plainly what setup does, and ask. Returns non-zero if the answer is no.
umami_setup_confirm() {
  gum style --bold "Background Umami"
  gum style "Adds Umami to Style → Background, and keeps a wallpaper you pick when you change themes."
  gum style "Nothing else is changed, and umami-uninstall puts everything back exactly as it was."
  echo
  gum confirm "Set up Background Umami now?" --affirmative "Set up" --negative "Not now"
}

# Count images in a folder, quickly, for the choice list.
umami_folder_count() {
  find -L "$1" -maxdepth "$UMAMI_MAX_DEPTH" -type f "${UMAMI_IMAGES[@]}" 2>/dev/null | head -n "$UMAMI_MAX_IMAGES" | wc -l
}

# Walk the folder tree with the arrow keys, folders only. (gum has a file
# picker, but it lists every file as well, which is noise when you want a
# folder.) Prints the chosen folder; returns 130 if canceled.
umami_folder_browse() {
  local dir=$1 choice entry label count use up="↑ Up one level"
  local -a options
  local -A target
  while true; do
    options=(); target=(); use=""
    if umami_safe_folder "$dir"; then
      use="✓ Use this folder  ($(umami_tilde "$dir"))"
      options+=("$use")
    fi
    [[ $dir == / ]] || options+=("$up")
    while IFS= read -r entry; do
      count=$(find -L "$entry" -maxdepth 1 -type f "${UMAMI_IMAGES[@]}" 2>/dev/null | head -n 999 | wc -l)
      label="${entry##*/}/"
      ((count > 0)) && label+="  ($count images)"
      options+=("$label")
      target[$label]=$entry
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' 2>/dev/null | sort)

    choice=$(gum choose --height 16 --header "$(umami_tilde "$dir")" "${options[@]}") || return 130
    if [[ -n $use && $choice == "$use" ]]; then
      printf '%s' "$dir"
      return 0
    elif [[ $choice == "$up" ]]; then
      dir=$(dirname "$dir")
    else
      dir=${target[$choice]}
    fi
  done
}

# Ask where the wallpapers live, without typing a path: pick one we found, let
# us create the usual one, or browse. Uses gum, which Omarchy depends on, so it
# looks like the rest of Omarchy's terminal tools. Returns 130 if canceled.
umami_folder_choose() {
  local dir label choice pictures default default_label other="Choose another folder…"
  local -a options=()
  local -A target=()
  pictures=$(umami_pictures_folder)
  default=$(umami_default_folder)

  while IFS= read -r dir; do
    label="Use $(umami_tilde "$dir")  ($(umami_folder_count "$dir") images)"
    options+=("$label"); target[$label]=$dir
    [[ $dir == "$default" ]] && default_label=$label
  done < <(umami_folder_candidates)
  if ((${#options[@]} == 0)); then
    label="Create $(umami_tilde "$default")"
    options+=("$label"); target[$label]=$default; default_label=$label
  fi
  options+=("$other")

  choice=$(gum choose --header "Where do your wallpapers live?" --selected "${default_label:-$other}" "${options[@]}") || return 130
  if [[ $choice == "$other" ]]; then
    [[ -d $pictures ]] || pictures=$HOME
    dir=$(umami_folder_browse "$pictures") || return 130
  else
    dir=${target[$choice]}
  fi
  [[ -n $dir ]] || return 130
  umami_folder_set "$dir"
}

# Make the folder if needed, check it is usable, and remember it.
umami_folder_set() { # <path>
  local dir=${1/#\~/$HOME}
  [[ -n $dir ]] || umami_die "no folder given"
  mkdir -p -- "$dir" 2>/dev/null || umami_die "cannot create $dir"
  umami_safe_folder "$dir" || umami_die "$dir cannot be used (it cannot be / or your home folder)"
  mkdir -p -- "$UMAMI_CONFIG"
  readlink -f -- "$dir" >"$UMAMI_CONFIG/folders"
}
