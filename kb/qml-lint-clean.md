---
id: omarchy-theme-forge.qml-lint-clean
project: omarchy-theme-forge
category: render
severity: warn
environment: omarchy-desktop
depends_on:
  - omarchy-theme-forge.style-duration-guarded
  - omarchy-theme-forge.style-easeout-guarded
---

# every QML file passes qmllint with the shell's imports resolved

## Claim
`qmllint` reports no warnings or errors against every top-level `.qml`
file, resolved against the real Omarchy shell's `qs.Commons`/`qs.Ui`
imports — filtered only for the three known linter limitations
run-checks.sh documents (singleton introspection, PanelWindow, and
`Process.exited`'s exit-status enum), plus the guarded `Style.duration`
and `Style.easeOut` members that Omarchy 4.0.6 lacks.

## Why
This is real static analysis against the actual import graph the
desktop uses, not lint running blind — catches a broken import or
reference lint alone would miss.

## Check
```bash
lint_bin="/usr/lib/qt6/bin/qmllint"
[ -x "$lint_bin" ] && [ -d /usr/share/omarchy/shell ]
lint_root=$(mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/theme-forge-lint.XXXXXX")
ln -sfn /usr/share/omarchy/shell "$lint_root/qs"
lint_out=$("$lint_bin" -I "$lint_root" -I /usr/lib/qt6/qml ./*.qml 2>&1)
rm -rf "$lint_root"
lint_out=$(printf '%s\n' "$lint_out" | grep -E "^(Warning|Error)" | grep -vE \
  'Unqualified access|not found on type "QObject"|QProcess::ExitStatus|uncreatable-type|Warnings occurred while importing|Member "(duration|easeOut)" not found on type "Style"')
[ -z "$lint_out" ]
```

## Depends On
- [[style-duration-guarded]]
- [[style-easeout-guarded]]
