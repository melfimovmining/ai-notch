#!/bin/bash
# Builds and runs the AI Notch test harnesses against the current sources.
#
# Each harness has its own @main, so they are compiled as separate binaries
# rather than linked together. They drive the real NotchPanelController, so a
# panel briefly appears on screen while they run.
set -uo pipefail

cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET="$(uname -m)-apple-macos14.0"

# Every app source except the two that define the app's own @main.
APP_SOURCES=(
  SideNotch/AdminAPI.swift
  SideNotch/AdminCredentials.swift
  SideNotch/CostMonitor.swift
  SideNotch/DetailCard.swift
  SideNotch/HoverWatchdog.swift
  SideNotch/Layout.swift
  SideNotch/LoginItem.swift
  SideNotch/Metric.swift
  SideNotch/NotchPanel.swift
  SideNotch/NotchView.swift
  SideNotch/PanelState.swift
  SideNotch/RingView.swift
  SideNotch/Shapes.swift
  SideNotch/UsageMonitor.swift
  SideNotch/UsageSnapshot.swift
)

mkdir -p build/tests
failures=0

run_harness() {
  local name="$1"; shift
  echo
  echo "── $name ──────────────────────────────────────────"
  if ! swiftc -parse-as-library -target "$TARGET" -sdk "$SDK" \
        -module-name SideNotchTests \
        "tools/tests/$name.swift" "${APP_SOURCES[@]}" \
        -o "build/tests/$name"; then
    echo "  BUILD FAILED"
    failures=$((failures + 1))
    return
  fi
  if ! "build/tests/$name" "$@"; then
    failures=$((failures + 1))
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

run_harness HitTestingTests
run_harness AutoCollapseTests
run_harness UsageMonitorTests "$TMPDIR_TEST"
run_harness CostMapperTests

echo
if [ "$failures" -eq 0 ]; then
  echo "All harnesses passed."
else
  echo "$failures harness(es) failed."
fi
exit "$failures"
