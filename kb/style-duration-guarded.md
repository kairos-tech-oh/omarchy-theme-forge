---
id: omarchy-theme-forge.style-duration-guarded
project: omarchy-theme-forge
category: ui
severity: warn
environment: any
depends_on: []
---

# Every Style.duration call falls back on shells that lack it

## Claim
Each `Style.duration(n)` in the QML is written as
`(Style.duration ? Style.duration(n) : n)`.

## Why
Omarchy 4.0.6 has no `Style.duration`, so an unguarded call throws a
TypeError and the animation drops to Qt's default timing.

## Check
```bash
! grep -rnE --include='*.qml' 'Style\.duration\(' . | grep -vE '\((Commons\.)?Style\.duration \? (Commons\.)?Style\.duration\('
```

## Depends On
None
