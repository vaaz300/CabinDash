#!/usr/bin/env bash
# Installs the simulator build, launches it, and checks it is still running a few seconds later.
# Also saves a screenshot. This catches a crash on launch, which a successful compile cannot.
#
# Needs: SIM_UDID (from select_simulator.py), and the path to CabinDash.app as the first argument.
#
# The check relies on how `launchctl list` prints a running app inside the simulator. That format has not been
# confirmed against a real run yet. If this step fails but the screenshot shows the app running, the check
# itself is wrong: say so, and it will be fixed rather than ignored.
set -euo pipefail

app="${1:?usage: launch_check.sh path/to/CabinDash.app [output-folder]}"
out="${2:-ci-artifacts}"
: "${SIM_UDID:?SIM_UDID is not set; the simulator selection step did not run}"

if [ ! -d "$app" ]; then
  echo "::error title=Launch check::$app does not exist, so there is nothing to launch."
  exit 1
fi

mkdir -p "$out"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
echo "App: $app"
echo "Bundle id: $bundle_id"

# Boots the simulator if it is not already running, and waits until it is ready.
xcrun simctl bootstatus "$SIM_UDID" -b

xcrun simctl install "$SIM_UDID" "$app"
# Pre-answer the location prompt so the screenshot shows the app, not a system dialog.
xcrun simctl privacy "$SIM_UDID" grant location "$bundle_id"
xcrun simctl location "$SIM_UDID" set 53.3498,-6.2603

xcrun simctl launch "$SIM_UDID" "$bundle_id" | tee "$out/launch.txt"
sleep 12

# The screenshot is taken before the verdict so there is always something to look at.
xcrun simctl io "$SIM_UDID" screenshot "$out/launch.png" || echo "Could not take a screenshot."

# Read the list into a variable first. Piping straight into `grep -q` can end the pipe early, and with
# `pipefail` that is reported as a failure even when the app was found.
running_list=$(xcrun simctl spawn "$SIM_UDID" launchctl list 2>&1 || true)
printf '%s\n' "$running_list" > "$out/launchctl-list.txt"

if ! grep -q "UIKitApplication:$bundle_id" <<<"$running_list"; then
  echo "::error title=Launch check::Cabin Dash was not in the simulator's process list 12 seconds after launch. It most likely crashed on start. See launch.png and launchctl-list.txt in the artifacts."
  crash_dir="$HOME/Library/Logs/DiagnosticReports"
  if ls "$crash_dir"/CabinDash* >/dev/null 2>&1; then
    mkdir -p "$out/crash-reports"
    cp "$crash_dir"/CabinDash* "$out/crash-reports/"
    echo "Crash report(s) copied to the artifact 'crash-reports' folder."
  else
    echo "No crash report found in $crash_dir."
  fi
  exit 1
fi

echo "Cabin Dash was still running after 12 seconds. Screenshot saved to $out/launch.png"
