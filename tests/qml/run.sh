#!/usr/bin/env bash
# Headless tests for the shell plugin's QML that runs outside the shell, and
# for the bounded clipboard read its paste uses.
set -euo pipefail
cd "$(dirname "$0")"
./read-clipboard.sh
runner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)
QT_QPA_PLATFORM=offscreen exec "$runner" -import stub -input . "$@"
