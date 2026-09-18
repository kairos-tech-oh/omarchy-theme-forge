---
id: omarchy-theme-forge.marketplace-preflight-passes
project: omarchy-theme-forge
category: manifest
severity: warn
environment: omarchy-desktop
depends_on: [omarchy-theme-forge.manifest-schema-valid]
---

# plugin passes the Omarchy marketplace preflight

## Claim
`omarchy plugin validate .` and the marketplace preflight scan both pass.

## Why
This is the same gate a real marketplace submission or update goes
through — catches capability/security findings the plugin's own checks
don't look for.

## Check
```bash
omarchy plugin validate . >/dev/null
bash "$HOME/.claude/skills/omarchy-plugin/scripts/preflight.sh" .
```

## Depends On
[[manifest-schema-valid]]
