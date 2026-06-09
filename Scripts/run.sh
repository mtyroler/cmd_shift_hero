#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle.sh "${1:-debug}"
open build/CommandShiftHero.app
