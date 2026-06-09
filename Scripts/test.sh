#!/bin/zsh
# `swift test` with the Testing.framework search paths CLT-only setups need.
set -euo pipefail
cd "$(dirname "$0")/.."
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
# CLT 26.5 ships lib_TestingInterop.dylib one directory off from where
# Testing.framework's install-name rpath expects it; add it explicitly.
INTEROP=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F$FWK -Xlinker -F$FWK \
    -Xlinker -rpath -Xlinker $FWK \
    -Xlinker -rpath -Xlinker $INTEROP "$@"
