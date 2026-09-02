#!/usr/bin/env bash
# Run every check the plugin has.
#
#   tools/run-checks.sh
#
# 1. The manifest matches what the shell enforces at load.
# 2. Palette.js, Sanitise.js and BarStyle.js behave under Node.
# 3. Both libraries behave under Qt's V4 engine -- which is the engine
#    omarchy-shell actually uses, and is not Node.
# 4. helper/reader.py refuses the images and paths it has to refuse.
# 5. Every QML file passes qmllint with the shell's own imports resolved.
#
# None of this touches the running desktop, writes a theme, or applies one.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

status=0
note() { printf '\n=== %s ===\n' "$1"; }

note "manifest"
if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate . >/dev/null 2>&1; then
    echo "  manifest.json is valid"
  else
    echo "  FAILED: omarchy plugin validate refused the manifest"
    status=1
  fi
else
  echo "  skipped: omarchy is not on PATH"
fi

note "Palette, Sanitise and BarStyle under Node"
if command -v node >/dev/null 2>&1; then
  node tools/check-palette.js || status=1
else
  echo "  skipped: node not installed (development-only dependency)"
fi

note "Qt V4 engine"
# Qt's `qml` runner suppresses console output on some builds, so the check
# communicates through its exit code instead. Offscreen because there is nothing
# to display and CI has no compositor.
qml_bin=""
for candidate in /usr/lib/qt6/bin/qml "$(command -v qml6 2>/dev/null)" "$(command -v qml 2>/dev/null)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] && qml_bin="$candidate" && break
done

if [ -n "$qml_bin" ]; then
  QT_QPA_PLATFORM=offscreen "$qml_bin" tools/check-qml-engine.qml
  code=$?
  if [ "$code" -eq 0 ]; then
    echo "  all V4 checks passed"
  else
    echo "  FAILED at check $code (see tools/check-qml-engine.qml for what that number is)"
    status=1
  fi
else
  echo "  skipped: no qml runner found"
fi

note "the image probe"
if command -v python3 >/dev/null 2>&1 && command -v magick >/dev/null 2>&1; then
  tools/check-probe.sh || status=1
else
  echo "  skipped: needs python3 and ImageMagick"
fi

note "qmllint"
lint_bin="/usr/lib/qt6/bin/qmllint"
if [ -x "$lint_bin" ] && [ -d /usr/share/omarchy/shell ]; then
  # qs.Commons and qs.Ui live inside the shell directory and are imported under
  # the `qs` prefix, so lint needs an import root that contains a `qs` pointing
  # at it. Built in a temporary directory: the plugin folder itself may not
  # contain a symlink -- the marketplace rejects git mode 120000 outright.
  lint_root=$(mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/theme-forge-lint.XXXXXX") || exit 1
  ln -sfn /usr/share/omarchy/shell "$lint_root/qs"
  lint_out=$("$lint_bin" -I "$lint_root" -I /usr/lib/qt6/qml ./*.qml 2>&1)
  rm -rf "$lint_root"

  # Three classes of warning are filtered, and each one is filtered because it
  # is a limit of the linter rather than a defect:
  #   - Style/Color/Border are QtObject-based singletons whose members qmllint
  #     cannot introspect; the shell's own files produce the same warnings.
  #   - Quickshell's PanelWindow is marked uncreatable for static analysis.
  #   - Process.exited carries a QProcess::ExitStatus qmllint cannot resolve.
  lint_out=$(printf '%s\n' "$lint_out" | grep -E "^(Warning|Error)" | grep -vE \
    'Unqualified access|not found on type "QObject"|QProcess::ExitStatus|uncreatable-type|Warnings occurred while importing')

  if [ -z "$lint_out" ]; then
    echo "  every QML file is clean"
  else
    printf '%s\n' "$lint_out"
    status=1
  fi
else
  echo "  skipped: needs qmllint and an Omarchy install"
fi

note "result"
if [ "$status" -eq 0 ]; then
  echo "everything passed"
else
  echo "one or more checks failed"
fi
exit "$status"
