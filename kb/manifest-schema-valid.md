---
id: omarchy-theme-forge.manifest-schema-valid
project: omarchy-theme-forge
category: manifest
severity: critical
environment: any
depends_on: []
---

# manifest.json is well-formed and its entry point exists

## Claim
`manifest.json` has `schemaVersion`, `id`, `name`, `version`, and
`entryPoints.panel` set, and that entry-point file actually exists.

## Why
This is the minimum Omarchy needs to load the plugin — a renamed or
deleted entry-point file would otherwise only surface as a silent
failure to load on the desktop.

## Check
```bash
m=manifest.json
jq -e '.schemaVersion and .id and .name and .version and .entryPoints.panel' "$m" >/dev/null
panel=$(jq -r '.entryPoints.panel' "$m")
[ -f "$panel" ]
```

## Depends On
None
