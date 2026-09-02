#!/usr/bin/python3

"""Bounded, symlink-refusing reads, and the image header probe built on one.

Python rather than bash for one reason: the three flags that make a read of an
untrusted path safe cannot be expressed by shell redirection.

    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    st = os.fstat(fd)

`>` and `<` in bash follow symlinks, and opening a FIFO blocks until a peer
appears -- which inside omarchy-shell means a hung widget and here would mean a
helper that never exits and a spinner that never stops. O_NOFOLLOW refuses the
symlink, O_NONBLOCK refuses to wait on the FIFO, and the fstat is taken on the
descriptor already open rather than on the path, so there is no second lookup
between the check and the read for anything to change under.

Everything below reads *once*, up to a ceiling, and validates the bytes it
actually got. Nothing here ever stats a path and then opens it.

    reader.py read  <path> <cap>     bytes to stdout; exit 4 if the file is bigger
    reader.py write <path> <cap> [mode]
                                     stdin to a file that must not already exist
    reader.py probe <path>           prints "<format> <width> <height>"
    reader.py image <path> <cap> <format>
                                     the whole image to stdout, from one open, once
                                     its header has passed the same probe

Exit codes are the interface; stderr is for a human.

    0  fine          3  not an image / unknown format   5  refused: too large
    2  unusable path 4  file exceeds the cap            6  bad usage
"""

import os
import stat
import struct
import sys

EXIT_OK = 0
EXIT_UNUSABLE = 2
EXIT_NOT_IMAGE = 3
EXIT_TOO_BIG = 4
EXIT_REFUSED = 5
EXIT_USAGE = 6

# Bounds on what an image may *declare*, checked before any decoder is handed
# the file. A few-KB PNG can claim 50000x50000; the point of reading the header
# ourselves is to never let that reach a decoder at all.
MAX_DIMENSION = 12000
MAX_PIXELS = 40_000_000

# Enough of a JPEG to reach its SOF marker past the usual EXIF/ICC blocks. A
# JPEG whose dimensions are not within this much of the start is refused rather
# than chased -- failing closed on an unusual file costs a wallpaper, and
# chasing it costs an unbounded read.
JPEG_SCAN_BYTES = 262144

READ_CAP_MAX = 4 * 1024 * 1024

# An encoded wallpaper. A 4K PNG measured 18 MiB; this is a hard ceiling on what
# `image` will hold before handing the bytes on.
IMAGE_CAP_MAX = 64 * 1024 * 1024

# Writes carry encoded images, which are an order of magnitude larger than any
# text file here; a measured 4K JPEG at quality 92 was 877 KiB.
WRITE_CAP_MAX = 32 * 1024 * 1024


def fail(code, message):
    print("theme-forge: " + message, file=sys.stderr)
    return code


def open_regular(path):
    """Open a path for reading, refusing anything that is not a regular file.

    Returns an open fd, or raises OSError/ValueError. The caller closes it.
    """
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise ValueError("not a regular file")
    except BaseException:
        os.close(fd)
        raise
    return fd


def read_bounded(path, cap):
    """Read at most cap+1 bytes, once.

    cap+1 rather than cap is the whole point: reading exactly cap bytes of an
    oversized file yields a valid-looking prefix that gets accepted, and for a
    state file can then be written back as a silently truncated document. Asking
    for one more byte than the ceiling is what makes "too big" detectable.
    """
    fd = open_regular(path)
    try:
        chunks = []
        remaining = cap + 1
        while remaining > 0:
            chunk = os.read(fd, min(remaining, 65536))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def check_dimensions(width, height):
    """Bound each axis before multiplying.

    A header may declare 2**32-1 on each side. Multiplying first can overflow a
    fixed-width product -- and in the shell version of this check can come back
    negative, which passes a naive `<=` test. Per-side first, product second.
    """
    if width < 1 or height < 1:
        return False
    if width > MAX_DIMENSION or height > MAX_DIMENSION:
        return False
    return width * height <= MAX_PIXELS


def png_size(data):
    # Both the 8-byte signature and the IHDR tag are anchored, which is what
    # makes bytes 16..23 the dimensions rather than whatever happens to sit at
    # that offset in some other format.
    if len(data) < 24:
        return None
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", data[16:24])
    return ("png", width, height)


def jpeg_size(data):
    if len(data) < 4 or data[0] != 0xFF or data[1] != 0xD8:
        return None
    index = 2
    limit = len(data)
    while index + 3 < limit:
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        # A fill byte is 0xFF followed by the real marker, so step one, not two.
        if marker == 0xFF:
            index += 1
            continue
        # The standalone markers carry no length field.
        if marker == 0x01 or 0xD0 <= marker <= 0xD9:
            index += 2
            continue
        if index + 4 > limit:
            return None
        length = struct.unpack(">H", data[index + 2:index + 4])[0]
        if length < 2:
            return None
        # SOF0..SOF15, minus the four that are not frame headers.
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            if index + 9 > limit:
                return None
            height, width = struct.unpack(">HH", data[index + 5:index + 9])
            return ("jpeg", width, height)
        if marker == 0xDA:  # start of scan: no frame header is coming
            return None
        index += 2 + length
    return None


def webp_size(data):
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    chunk = data[12:16]
    if chunk == b"VP8X":
        width = int.from_bytes(data[24:27], "little") + 1
        height = int.from_bytes(data[27:30], "little") + 1
        return ("webp", width, height)
    if chunk == b"VP8 ":
        if len(data) < 30 or data[23:26] != b"\x9d\x01\x2a":
            return None
        width = struct.unpack("<H", data[26:28])[0] & 0x3FFF
        height = struct.unpack("<H", data[28:30])[0] & 0x3FFF
        return ("webp", width, height)
    if chunk == b"VP8L":
        if len(data) < 25 or data[20] != 0x2F:
            return None
        bits = int.from_bytes(data[21:25], "little")
        width = (bits & 0x3FFF) + 1
        height = ((bits >> 14) & 0x3FFF) + 1
        return ("webp", width, height)
    return None


def probe_bytes(head):
    """(kind, width, height) for a header that passes, or an exit code."""
    for parser in (png_size, jpeg_size, webp_size):
        found = parser(head)
        if found is None:
            continue
        kind, width, height = found
        if not check_dimensions(width, height):
            return fail(
                EXIT_REFUSED,
                "that image declares %dx%d, past the %dx%d / %d megapixel ceiling"
                % (width, height, MAX_DIMENSION, MAX_DIMENSION, MAX_PIXELS // 1_000_000),
            )
        return (kind, width, height)
    return fail(EXIT_NOT_IMAGE, "that file is not a PNG, JPEG or WebP")


def command_probe(path):
    try:
        head = read_bounded(path, JPEG_SCAN_BYTES)
    except OSError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error.strerror)
    except ValueError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error)

    found = probe_bytes(head)
    if isinstance(found, int):
        return found
    print("%s %d %d" % found)
    return EXIT_OK


def command_image(path, cap_text, expected):
    """Stream an image to stdout so ImageMagick never sees the path.

    One open, one read: the bytes the decoder gets are the bytes the header
    check passed, so nothing can be swapped between the probe and the decode.
    The format is pinned by the caller and refused on a mismatch rather than
    left for the decoder to guess -- and a path never reaches ImageMagick,
    which would otherwise parse `coder:`, `[scene]` and `@file` out of it.
    """
    try:
        cap = int(cap_text)
    except ValueError:
        return fail(EXIT_USAGE, "cap must be a number")
    if cap < 1 or cap > IMAGE_CAP_MAX:
        return fail(EXIT_USAGE, "cap out of range")
    if expected not in ("png", "jpeg", "webp"):
        return fail(EXIT_USAGE, "format must be png, jpeg or webp")

    try:
        data = read_bounded(path, cap)
    except OSError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error.strerror)
    except ValueError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error)
    if len(data) > cap:
        return fail(EXIT_TOO_BIG, "that image is larger than %d bytes" % cap)

    found = probe_bytes(data[:JPEG_SCAN_BYTES])
    if isinstance(found, int):
        return found
    if found[0] != expected:
        return fail(EXIT_REFUSED, "that file is a %s now, not the %s that was checked" % (found[0], expected))

    write_all(sys.stdout.buffer.fileno(), data)
    return EXIT_OK


def command_read(path, cap_text):
    try:
        cap = int(cap_text)
    except ValueError:
        return fail(EXIT_USAGE, "cap must be a number")
    if cap < 1 or cap > READ_CAP_MAX:
        return fail(EXIT_USAGE, "cap out of range")

    try:
        data = read_bounded(path, cap)
    except FileNotFoundError:
        return EXIT_UNUSABLE
    except OSError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error.strerror)
    except ValueError as error:
        return fail(EXIT_UNUSABLE, "cannot read that file (%s)" % error)

    if len(data) > cap:
        return fail(EXIT_TOO_BIG, "that file is larger than %d bytes" % cap)

    write_all(sys.stdout.buffer.fileno(), data)
    return EXIT_OK


def write_all(fd, data):
    # os.write may stop short; a partial state file that still parses is
    # exactly the silent-truncation case the caps exist to prevent.
    view = memoryview(data)
    while len(view):
        view = view[os.write(fd, view):]


def command_write(path, cap_text, mode_text="0600"):
    """Write stdin to a path that must not already exist.

    O_CREAT | O_EXCL | O_NOFOLLOW is the whole point. A fixed scratch name --
    `colors.toml.new`, `draft.json.new` -- is a name anyone who can write to the
    directory can create first, as a symlink pointing at something of theirs; a
    plain `> "$tmp"` in the shell then truncates their target instead of ours.
    O_EXCL refuses to open anything that is already there, so there is nothing
    to redirect, and the caller renames the result into place afterwards.
    """
    try:
        cap = int(cap_text)
    except ValueError:
        return fail(EXIT_USAGE, "cap must be a number")
    if cap < 1 or cap > WRITE_CAP_MAX:
        return fail(EXIT_USAGE, "cap out of range")

    data = sys.stdin.buffer.read(cap + 1)
    if len(data) > cap:
        return fail(EXIT_TOO_BIG, "more than %d bytes arrived on stdin" % cap)

    try:
        mode = int(mode_text, 8)
    except ValueError:
        return fail(EXIT_USAGE, "mode must be octal")
    if mode < 0 or mode > 0o777:
        return fail(EXIT_USAGE, "mode out of range")

    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    except FileExistsError:
        return fail(EXIT_UNUSABLE, "%s already exists" % path)
    except OSError as error:
        return fail(EXIT_UNUSABLE, "cannot write there (%s)" % error.strerror)

    try:
        write_all(fd, data)
    finally:
        os.close(fd)
    return EXIT_OK


def main(argv):
    if len(argv) < 3:
        return fail(EXIT_USAGE,
                    "usage: reader.py read <path> <cap> | write <path> <cap> [mode]"
                    " | probe <path> | image <path> <cap> <format>")
    command = argv[1]
    if command == "probe" and len(argv) == 3:
        return command_probe(argv[2])
    if command == "read" and len(argv) == 4:
        return command_read(argv[2], argv[3])
    if command == "write" and len(argv) in (4, 5):
        return command_write(argv[2], argv[3], argv[4] if len(argv) == 5 else "0600")
    if command == "image" and len(argv) == 5:
        return command_image(argv[2], argv[3], argv[4])
    return fail(EXIT_USAGE, "unknown command")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
