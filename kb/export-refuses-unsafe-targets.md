---
id: omarchy-theme-forge.export-refuses-unsafe-targets
project: omarchy-theme-forge
category: logic
severity: critical
environment: omarchy-desktop
depends_on: []
---

# publishing a theme refuses every unsafe target

## Claim
`tools/check-export.sh` passes: `export` refuses a relative parent, a
symlinked parent or target, a target that isn't a theme repo, and an
icon set not on the allowed list; `verify` reports what it should for a
complete and an incomplete theme.

## Why
Publishing is the one thing this plugin does that writes outside its own
config directory, into a path the user names rather than one the plugin
owns — every case here is a real failure mode with a real cost, from
overwriting someone else's work to arbitrary text in a gsettings value.

## Check
```bash
bash tools/check-export.sh
```

## Depends On
None
