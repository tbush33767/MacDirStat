#!/bin/bash
# Runs the test suite under Command Line Tools (no Xcode).
#
# The CLT ships Testing.framework but (a) SwiftPM passes its directory as -I
# instead of -F, and (b) the _Testing_Foundation cross-import overlay framework
# has no Swift module files. Hence the explicit -F and the overlay opt-out.
set -euo pipefail
cd "$(dirname "$0")"
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test \
  -Xswiftc -F"$FWK" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F"$FWK" \
  -Xlinker -rpath -Xlinker "$FWK" \
  "$@"
