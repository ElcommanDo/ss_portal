#!/usr/bin/env bash
# Smart System Timesheet - one-time Android setup (macOS / Linux / CI)
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "Flutter is not on PATH"; exit 1; }
if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  flutter create --platforms=android --org com.smartsystem --project-name smart_system_timesheet .
fi
cp -R android_overrides/. android/
flutter pub get
echo "Done. flutter run  |  flutter build apk --release"
