#!/usr/bin/env bash
# Headless tests for the shell plugin's QML that runs outside the shell.
set -euo pipefail
cd "$(dirname "$0")"
runner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)
QT_QPA_PLATFORM=offscreen exec "$runner" -import stub -input . "$@"
