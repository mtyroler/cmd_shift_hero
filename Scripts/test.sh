#!/bin/zsh
# `swift test` with the Testing.framework search paths CLT-only setups need.
set -euo pipefail
cd "$(dirname "$0")/.."
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test -Xswiftc -F$FWK -Xlinker -F$FWK -Xlinker -rpath -Xlinker $FWK "$@"
