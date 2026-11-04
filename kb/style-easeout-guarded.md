---
id: omarchy-theme-forge.style-easeout-guarded
project: omarchy-theme-forge
category: ui
severity: warn
environment: any
depends_on: []
---

# Every Style.easeOut curve falls back on shells that lack it

## Claim
Each `easing.bezierCurve: Style.easeOut` in the QML carries an
`|| [0.33, 1, 0.68, 1, 1, 1]` fallback.

## Why
Omarchy 4.0.6 has no `Style.easeOut`; an undefined bezier curve leaves an
empty spline, so the animation runs linear and the shell logs a warning.

## Check
```bash
! grep -rnE --include='*.qml' 'Style\.easeOut' . | grep -vF 'Style.easeOut || [0.33, 1, 0.68, 1, 1, 1]'
```

## Depends On
None
