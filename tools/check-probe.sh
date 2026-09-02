#!/usr/bin/env bash
# What helper/reader.py has to refuse, and prove it refuses without hanging.
#
# The image path is the only place this plugin hands an untrusted file to a
# decoder, and the decoder lives one process away from omarchy-shell. So each
# case below is a real failure mode with a real cost:
#
#   an 8000x8000 PNG          measured 562 MiB peak RSS inside a shell process
#   a FIFO                    an open() that never returns is a helper that
#                             never exits and a spinner that never stops
#   a symlink                 reads whatever the link's author chose
#   a file that is not one    ImageMagick guessing at a format it was handed
#
# Fixtures are built in a temporary directory and removed afterwards. Nothing
# here touches the user's themes.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
reader="$PWD/helper/reader.py"

# $XDG_RUNTIME_DIR rather than /tmp for the same reason the plugin itself uses
# it: a predictable path under a world-writable directory can be pre-created by
# another local user. mktemp's suffix already makes this one unpredictable; this
# just keeps the whole repo free of a /tmp path a reviewer has to think about.
work=$(mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/theme-forge-check.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

status=0
check() {
  local label="$1" want="$2"; shift 2
  local out got
  # stdout is binary for the read cases, so only the exit code and stderr are
  # kept -- capturing binary in a command substitution warns about null bytes.
  out=$(timeout 15 "$@" 2>&1 >/dev/null)
  got=$?
  if [ "$got" = "$want" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (wanted exit %s, got %s: %s)\n' "$label" "$want" "$got" "$out"
    status=1
  fi
}

magick -size 400x300 gradient:'#8b0000-#4682b4' "$work/ok.png"  2>/dev/null
magick -size 400x300 gradient:'#8b0000-#4682b4' "$work/ok.jpg"  2>/dev/null
magick -size 400x300 gradient:'#2e8b57-#ffd700' "$work/ok.webp" 2>/dev/null
magick -size 8000x8000 xc:'#123456' "$work/huge.png" 2>/dev/null
printf 'not an image at all' > "$work/bogus.png"
# A run of identical bytes: this is the shape that makes `od` collapse its
# output to a `*` when -v is missing, which refuses every image and looks
# exactly like working code.
dd if=/dev/zero of="$work/zeros.png" bs=4096 count=1 status=none
mkfifo "$work/fifo.png"
ln -sf /etc/passwd "$work/link.png"

check "a PNG is accepted"                  0 python3 "$reader" probe "$work/ok.png"
check "a JPEG is accepted"                 0 python3 "$reader" probe "$work/ok.jpg"
check "a WebP is accepted"                 0 python3 "$reader" probe "$work/ok.webp"
check "an 8000x8000 PNG is refused"        5 python3 "$reader" probe "$work/huge.png"
check "a non-image is refused"             3 python3 "$reader" probe "$work/bogus.png"
check "a run of identical bytes is refused as a non-image, not as a parse failure" \
                                           3 python3 "$reader" probe "$work/zeros.png"
check "a symlink is refused"               2 python3 "$reader" probe "$work/link.png"
check "a FIFO is refused and does not block" \
                                           2 python3 "$reader" probe "$work/fifo.png"
check "a missing file is refused"          2 python3 "$reader" probe "$work/nothing.png"

# The bounded reader: cap+1 is requested so an oversized file is *detectable*
# rather than silently truncated to a plausible prefix.
dd if=/dev/urandom of="$work/small.bin" bs=100 count=1 status=none
dd if=/dev/urandom of="$work/big.bin" bs=5000 count=1 status=none
check "a file under the cap is read"       0 python3 "$reader" read "$work/small.bin" 4096
check "a file over the cap is refused"     4 python3 "$reader" read "$work/big.bin" 4096
check "reading a FIFO is refused"          2 python3 "$reader" read "$work/fifo.png" 4096
check "reading a symlink is refused"       2 python3 "$reader" read "$work/link.png" 4096

# A file of exactly the cap is the boundary case that a cap-sized read would
# accept and a cap+1 read correctly lets through.
dd if=/dev/urandom of="$work/exact.bin" bs=4096 count=1 status=none
check "a file of exactly the cap is read"  0 python3 "$reader" read "$work/exact.bin" 4096

# The image stream: what ImageMagick is actually fed. The format is pinned by
# the caller, so a file that is not what the probe said it was is refused
# rather than handed to whichever decoder guesses at it.
check "an image streams under its pinned format" \
                                           0 python3 "$reader" image "$work/ok.png" 1048576 png
check "a format mismatch is refused"       5 python3 "$reader" image "$work/ok.png" 1048576 jpeg
check "an oversized image is refused"      4 python3 "$reader" image "$work/ok.png" 512 png
check "an oversized declaration is refused" \
                                           5 python3 "$reader" image "$work/huge.png" 67108864 png
check "streaming a symlink is refused"     2 python3 "$reader" image "$work/link.png" 1048576 png
check "streaming a FIFO is refused"        2 python3 "$reader" image "$work/fifo.png" 1048576 png
check "an unknown format is refused"       6 python3 "$reader" image "$work/ok.png" 1048576 gif
# The bytes have to be the file, whole and unchanged.
if cmp -s "$work/ok.jpg" <(python3 "$reader" image "$work/ok.jpg" 1048576 jpeg); then
  printf '  ok    %s\n' "the streamed bytes are the file"
else
  printf '  FAIL  %s\n' "the streamed bytes are not the file"; status=1
fi

if [ "$status" -eq 0 ]; then
  echo "  the probe refuses everything it has to"
fi
exit "$status"
