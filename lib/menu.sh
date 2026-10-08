# shellcheck shell=bash
# Adding rows to ~/.config/omarchy/extensions/omarchy-menu.jsonc without hurting it.
#
# Omarchy reads that file by deleting whole-line // comments and trailing commas,
# then calling JSON.parse. If that fails it silently drops every user menu row,
# so each write is checked against the same rules first. Our rows sit between two
# marker lines. We only ever add or delete those whole lines, which means
# uninstalling gives back the original file byte for byte.

UMAMI_MENU_BEGIN='// >>> umami managed block (Background Umami) - do not edit between these lines >>>'
UMAMI_MENU_END='// <<< umami managed block <<<'
UMAMI_DEFAULT_MENU="${OMARCHY_PATH:-/usr/share/omarchy}/default/omarchy/omarchy-menu.jsonc"

# The real file, following a dotfile-manager symlink so we edit the target.
umami_menu_file() { readlink -f -- "$OMARCHY_USER/extensions/omarchy-menu.jsonc"; }

# Omarchy's own two substitutions (MenuModel.stripJsonc), then standard JSON.
umami_menu_strip() { perl -0777 -pe 's/^\s*\/\/[^\n]*(\n|$)//gm; s/,(\s*[}\]])/$1/g'; }
umami_menu_parses() { umami_menu_strip | jq -e 'type == "object"' >/dev/null 2>&1; }
umami_menu_keys() { umami_menu_strip | jq -r 'keys[]'; }
umami_menu_uses_items() { umami_menu_strip | jq -e 'has("items")' >/dev/null 2>&1; }

# Print the file without our block (stdin to stdout).
umami_menu_drop() {
  perl -ne 'if (/^\s*\/\/ >>> umami managed block/) { $skip = 1; next }
            if ($skip) { $skip = 0 if /^\s*\/\/ <<< umami managed block/; next }
            print'
}

# Print the file with $1 inserted on the lines right after the opening brace,
# using the file'"'"'s own line endings (stdin to stdout).
umami_menu_add() {
  UMAMI_BLOCK=$1 perl -e '
    local $/;
    my @lines = split /(?<=\n)/, <STDIN>;
    for my $i (0 .. $#lines) {
      next if $lines[$i] =~ m{^\s*(//.*)?$};
      $lines[$i] =~ /\{[ \t]*(\r?\n)\z/ or die "the opening { must end its line\n";
      my $eol = $1;
      splice @lines, $i + 1, 0, map { "$_$eol" } split /\n/, $ENV{UMAMI_BLOCK};
      print @lines;
      exit 0;
    }
    die "no opening { found\n";'
}

# none | one | broken (a marker without its partner, or more than one block)
umami_menu_block_state() {
  local begins ends
  begins=$(grep -cF "$UMAMI_MENU_BEGIN" "$1") || true
  ends=$(grep -cF "$UMAMI_MENU_END" "$1") || true
  if ((begins == 0 && ends == 0)); then echo none
  elif ((begins == 1 && ends == 1)); then echo one
  else echo broken; fi
}

# Where the edited copy is built: next to the real file so the final rename is
# atomic. Scripts remove it on exit (see umami_menu_cleanup), so a failed run
# leaves nothing behind.
umami_menu_scratch() { printf '%s.umami-new' "$1"; }
umami_menu_cleanup() { rm -f -- "$(umami_menu_scratch "$(umami_menu_file)")"; }

# Omarchy's own Background row, as JSON. Fails if it is missing or has no action.
umami_stock_background() {
  umami_menu_strip 2>/dev/null <"$UMAMI_DEFAULT_MENU" |
    jq -ec '.["style.background"] | select((.action // "") != "")'
}

# Our rows. Background becomes a submenu: Theme Backgrounds runs the stock
# action (then drops the pin if a different wallpaper was chosen), Umami holds
# ours. A user entry replaces every field of the stock row it names, so icon,
# label and aliases are carried over. Glyphs are written as \uXXXX so an editor
# cannot strip them. The Umami row hides itself if our scripts have gone.
umami_menu_block() { # <plugin root> <stock row json>
  jq -n -r --argjson stock "$2" --arg root "$1" '
    def run($cmd; $arg): ($root + "/" + $cmd | @sh) + (if $arg == "" then "" else " " + $arg end);
    def shuffle($arg): run("libexec/umami-shuffle"; $arg);
    def row($id; $label; $action): {key: $id, value: {icon: $stock.icon, label: $label, action: $action}};
    def checked($id; $label; $action; $test): {key: $id, value: {icon: $stock.icon, label: $label, action: $action, checked: $test}};
    def menu($id; $label): {key: $id, value: {icon: $stock.icon, label: $label}};
    [
      {key: "style.background", value: ($stock | del(.action))},
      {key: "style.background.stock", value: {icon: $stock.icon, label: "Theme Backgrounds", description: "Stock picker",
        action: ($stock.action + "; " + run("libexec/umami-unpin"; ""))}},
      {key: "style.background.umami", value: {icon: $stock.icon, label: "Umami", description: "Custom, all, shuffle",
        aliases: ["umami", "background umami", "wallpapers", "custom background", "shuffle"],
        when: ("test -x " + ($root + "/bin/umami-browse" | @sh))}},
      row("style.background.umami.folder"; "Custom Folder"; run("bin/umami-browse"; "folder")),
      row("style.background.umami.all"; "All Backgrounds"; run("bin/umami-browse"; "all")),
      menu("style.background.umami.shuffle"; "Shuffle"),
      row("style.background.umami.shuffle.now"; "Shuffle Now"; shuffle("now")),
      (5, 15, 30, 60 | checked("style.background.umami.shuffle.\(.)"; "Every \(.) Min"; shuffle("start \(.)"); shuffle("is interval \(.)"))),
      checked("style.background.umami.shuffle.custom"; "Custom\u2026"; shuffle("custom"); shuffle("is custom")),
      checked("style.background.umami.shuffle.off"; "Off"; shuffle("stop"); shuffle("is off")),
      menu("style.background.umami.from"; "Shuffle From"),
      checked("style.background.umami.from.theme"; "This Theme"; shuffle("scope theme"); shuffle("is scope theme")),
      checked("style.background.umami.from.folder"; "Custom Folder"; shuffle("scope folder"); shuffle("is scope folder")),
      checked("style.background.umami.from.all"; "All Backgrounds"; shuffle("scope all"); shuffle("is scope all")),
      row("style.background.umami.open"; "Open Folder"; run("bin/umami-folder"; "open")),
      row("style.background.umami.change"; "Change Folder\u2026"; "omarchy-launch-floating-terminal-with-presentation " + run("bin/umami-folder"; "choose")),
      row("style.background.umami.remove"; "Remove Added"; run("bin/umami-remove"; "")),
      row("style.background.umami.restore"; "Restore Default"; run("bin/umami-restore"; ""))
    ] | from_entries
    | to_entries[] | "  \(.key | @json): \(.value | tojson),"' |
    perl -CSD -pe 's/([^\x00-\x7f])/sprintf("\\u%04x", ord $1)/ge' |
    { printf '  %s\n' "$UMAMI_MENU_BEGIN"; cat; printf '  %s\n' "$UMAMI_MENU_END"; }
}

umami_menu_install() { # <plugin root>
  local file stock block new want got existing
  file=$(umami_menu_file)
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || printf '{\n}\n' >"$file"

  umami_menu_parses <"$file" || umami_die "$file is not a valid Omarchy menu file. Fix or move it first; a broken file hides every user menu row."
  umami_menu_uses_items <"$file" && umami_die "$file uses the {\"items\": …} layout, which Umami does not edit."
  [[ $(umami_menu_block_state "$file") != "broken" ]] || umami_die "$file has a damaged Umami block (a missing or doubled marker). Delete the lines between the markers and run again."
  stock=$(umami_stock_background) || umami_die "no stock style.background row in $UMAMI_DEFAULT_MENU; this Omarchy lays out its menu differently."
  existing=$(umami_menu_drop <"$file" | umami_menu_keys)
  if grep -qx 'style.background' <<<"$existing"; then
    umami_die "$file already defines style.background (another plugin, or your own edit). Overriding it twice would break one of them."
  fi

  block=$(umami_menu_block "$1" "$stock") && [[ $block == *'"style.background.umami.all"'* ]] ||
    umami_die "could not build the menu rows (is jq working?); nothing was changed."
  new=$(umami_menu_scratch "$file")
  umami_menu_drop <"$file" | umami_menu_add "$block" >"$new" || umami_die "could not place the block in $file"

  # Same keys as before plus ours, and it must still parse.
  want=$({ umami_menu_drop <"$file" | umami_menu_keys; sed -n 's/^  "\([^"]*\)":.*/\1/p' <<<"$block"; } | sort -u)
  got=$(umami_menu_keys <"$new" | sort -u)
  { umami_menu_parses <"$new" && [[ $want == "$got" ]]; } || umami_die "the edited menu failed validation; nothing was changed."

  cp -p -- "$file" "$file.umami-backup"
  chmod --reference="$file" "$new"
  mv -f -- "$new" "$file"
}

umami_menu_uninstall() {
  local file new
  file=$(umami_menu_file)
  [[ -f $file && $(umami_menu_block_state "$file") != "none" ]] || return 0
  [[ $(umami_menu_block_state "$file") == "one" ]] || umami_die "$file has a damaged Umami block; delete the marker lines by hand."

  new=$(umami_menu_scratch "$file")
  umami_menu_drop <"$file" >"$new"
  umami_menu_parses <"$new" || umami_die "removing the block would leave an invalid menu file; nothing was changed."
  chmod --reference="$file" "$new"
  mv -f -- "$new" "$file"
  rm -f -- "$file.umami-backup"
}
