#!/bin/sh
# Isolated staging and scoped process cleanup; never alters the host root home.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "$ROOT/tests/kindle-sim/arm-smoke.py"
