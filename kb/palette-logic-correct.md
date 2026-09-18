---
id: omarchy-theme-forge.palette-logic-correct
project: omarchy-theme-forge
category: logic
severity: critical
environment: any
depends_on: []
---

# palette rolling and derivation is correct under Node

## Claim
`tools/check-palette.js` passes: `Palette.js`, `Sanitise.js`, and
`BarStyle.js` behave correctly under Node.

## Why
Every theme this plugin can produce — rolled, tuned by hand, or seeded
from a wallpaper — goes through this derivation. Wrong math here means a
wrong theme, silently.

## Check
```bash
node tools/check-palette.js
```

## Depends On
None
