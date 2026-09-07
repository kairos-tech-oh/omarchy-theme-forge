#!/usr/bin/env bash
# What `verify` reports and what `export` refuses.
#
# Publishing is the one thing this plugin does that writes outside
# ~/.config/omarchy/themes, into a directory the user names rather than one the
# plugin owns. So each case below is a real failure mode with a real cost:
#
#   a target that is not a theme repo   an export into somebody else's work
#   a symlinked parent or target        writes to a directory nobody named
#   an icon set that is not on the list  arbitrary text into a gsettings value
#   a colors.toml Omarchy cannot read   a theme that is silently wrong
#
# The whole suite runs against a throwaway HOME, so nothing here can see, write
# or apply one of the user's own themes.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
helper="$PWD/helper/theme-forge"

command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || {
  echo "  skipped: needs ImageMagick"; exit 0; }

work=$(mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/theme-forge-export.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

# A throwaway HOME with a git identity of its own, so `export` reaches its
# commit rather than stopping at "set a git identity" and leaving half the
# path untested.
export HOME="$work/home"
mkdir -p "$HOME/.config/omarchy/themes" "$work/pub"
printf '[user]\n\tname = Check\n\temail = check@example.invalid\n' > "$HOME/.gitconfig"

status=0
check() {
  local label="$1" want="$2"; shift 2
  local out got
  out=$(timeout 60 "$@" 2>&1)
  got=$?
  if [ "$got" = "$want" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (wanted exit %s, got %s: %s)\n' "$label" "$want" "$got" "$(printf '%s' "$out" | head -1)"
    status=1
  fi
}

# Says <state> for <label> in the report, whatever the detail happens to be.
says() {
  local label="$1" want="$2" name="$3"
  local got
  got=$(timeout 30 "$helper" verify "$name" 2>/dev/null | awk -F'\t' -v l="$want" '$2 == l { print $1 }')
  if [ "$got" = "$label" ]; then
    printf '  ok    verify says %s for %s\n' "$label" "$want"
  else
    printf '  FAIL  verify says %s for %s (wanted %s)\n' "${got:-nothing}" "$want" "$label"
    status=1
  fi
}

# The palette comes from Palette.js rather than being typed here, so what is
# checked is the file the panel actually sends.
node - <<'JS' > "$work/colors.toml" 2>/dev/null
const fs = require("fs"), vm = require("vm")
const src = fs.readFileSync("Palette.js", "utf8").replace(/^\s*\.pragma\s+library\s*/, "")
const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx)
process.stdout.write(ctx.toToml(ctx.derive(ctx.rollSpec(99, "dark")), "good"))
JS
if [ ! -s "$work/colors.toml" ]; then
  echo "  skipped: needs node to generate a palette"
  exit 0
fi

"$helper" save good Yaru-sage < "$work/colors.toml" >/dev/null 2>&1
magick -size 64x36 xc:'#101014' "$HOME/.config/omarchy/themes/good/backgrounds/0-good.jpg" 2>/dev/null

# ----------------------------------------------------------------- the report
says ok   "colors.toml"        good
says ok   "icons.theme"        good
says ok   "backgrounds"        good
says warn "preview.png"        good
check "verify passes a complete theme" 0 "$helper" verify good

magick -size 200x200 xc:'#101014' "$work/grab.png" 2>/dev/null
check "a grab becomes preview.png" 0 "$helper" preview good "$work/grab.png" "#101014"
says ok "preview.png" good

mkdir -p "$HOME/.config/omarchy/themes/half/backgrounds"
printf 'mode = "dark"\naccent = "#ffffff"\n' > "$HOME/.config/omarchy/themes/half/colors.toml"
check "verify refuses a theme missing colours" 1 "$helper" verify half
printf 'mode = "dark"\nevil = "`id`"\n' > "$HOME/.config/omarchy/themes/half/colors.toml"
check "verify refuses a line Omarchy cannot read" 1 "$helper" verify half
check "verify refuses a theme that is not there" 1 "$helper" verify nosuchtheme

touch "$HOME/.config/omarchy/themes/good/neovim.lua"
says warn "dropped once cloned" good
rm -f "$HOME/.config/omarchy/themes/good/neovim.lua"

# ---------------------------------------------------------------- the icon set
check "an icon set off the list is refused" 1 \
  bash -c "printf 'mode = \"dark\"\n' | '$helper' save good 'Yaru-evil; rm -rf /'"
check "an icon set with a newline is refused" 1 \
  bash -c "printf 'mode = \"dark\"\n' | '$helper' save good 'Yaru-blue
Yaru-red'"

# ------------------------------------------------------------------- the export
check "export builds a repository"     0 "$helper" export good "$work/pub"
check "the repository is committed"    0 git -C "$work/pub/omarchy-good-theme" rev-parse HEAD
check "re-exporting is fine"           0 "$helper" export good "$work/pub"

for file in colors.toml icons.theme preview.png README.md LICENSE .gitignore backgrounds/0-good.jpg; do
  if [ -f "$work/pub/omarchy-good-theme/$file" ]; then
    printf '  ok    the repository has %s\n' "$file"
  else
    printf '  FAIL  the repository is missing %s\n' "$file"
    status=1
  fi
done

# A README the author has edited is theirs, and a second export must not
# quietly put the template back.
printf 'my own words\n' > "$work/pub/omarchy-good-theme/README.md"
"$helper" export good "$work/pub" >/dev/null 2>&1
if [ "$(cat "$work/pub/omarchy-good-theme/README.md")" = "my own words" ]; then
  printf '  ok    an edited README survives a re-export\n'
else
  printf '  FAIL  a re-export overwrote the README\n'
  status=1
fi

# The theme itself must stay a theme Theme Forge can still save to, which means
# no .git of its own.
if [ -e "$HOME/.config/omarchy/themes/good/.git" ]; then
  printf '  FAIL  export left a .git inside the theme\n'
  status=1
else
  printf '  ok    the theme itself is still not a repository\n'
fi

# ---------------------------------------------------------------- the refusals
check "a relative parent is refused"   1 "$helper" export good "relative/path"
check "a parent that is not there"     1 "$helper" export good "$work/missing"
check "a parent that is a file"        1 "$helper" export good "$work/colors.toml"
ln -sfn "$work/pub" "$work/publink"
check "a symlinked parent is refused"  1 "$helper" export good "$work/publink"
check "a traversing name is refused"   1 "$helper" export "../../etc" "$work/pub"

mkdir -p "$work/pub2/omarchy-good-theme"
printf 'someone else\n' > "$work/pub2/omarchy-good-theme/notes.txt"
check "a target that is not a theme"   1 "$helper" export good "$work/pub2"
rm -rf "$work/pub2/omarchy-good-theme"
ln -sfn /etc "$work/pub2/omarchy-good-theme"
check "a symlinked target is refused"  1 "$helper" export good "$work/pub2"

exit "$status"
