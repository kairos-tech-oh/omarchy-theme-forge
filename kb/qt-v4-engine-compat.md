---
id: omarchy-theme-forge.qt-v4-engine-compat
project: omarchy-theme-forge
category: logic
severity: critical
environment: omarchy-desktop
depends_on: []
---

# palette libraries behave under Qt's real engine, not just Node

## Claim
`tools/check-qml-engine.qml` passes under Qt's V4 engine (`qml`,
offscreen) — the engine omarchy-shell actually uses, not Node's.

## Why
`check-palette.js` proves the logic works under Node; this proves it
also works under the engine that actually runs it on the desktop. The
two engines have diverged before.

## Check
```bash
qml_bin=""
for candidate in /usr/lib/qt6/bin/qml qml6 qml; do
  command -v "$candidate" >/dev/null 2>&1 && qml_bin="$(command -v "$candidate")" && break
done
[ -n "$qml_bin" ]
QT_QPA_PLATFORM=offscreen "$qml_bin" tools/check-qml-engine.qml
```

## Depends On
None
