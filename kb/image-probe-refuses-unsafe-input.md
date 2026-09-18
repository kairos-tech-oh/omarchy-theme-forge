---
id: omarchy-theme-forge.image-probe-refuses-unsafe-input
project: omarchy-theme-forge
category: logic
severity: critical
environment: omarchy-desktop
depends_on: []
---

# the image probe refuses everything it has to

## Claim
`tools/check-probe.sh` passes: `helper/reader.py` refuses an oversized
image, a non-image, a symlink, and a FIFO — without hanging.

## Why
The wallpaper-seed path is the only place this plugin hands an
untrusted file to a decoder one process away from omarchy-shell — an
8000x8000 PNG measured 562 MiB peak RSS before this existed, and a FIFO
read that never returns is a helper that never exits.

## Check
```bash
bash tools/check-probe.sh
```

## Depends On
None
