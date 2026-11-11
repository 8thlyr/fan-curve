#!/bin/sh
# Builds `fan-curve-curve` for the demo recording and puts it on PATH.
#
# The app is macOS-only, but FanCurveCore (the curve math, the scene budget,
# the RPM mapping) is plain Swift plus Foundation, so it builds on Linux. This
# builds that one product in Docker with a static Swift stdlib and copies it
# into /tmp/fan-curve-demo.
#
# `vhs docs/demo.tape` then records the real binary's output. Nothing here
# imitates the app; it runs the same FanCurveCore code the app runs.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
demo=${1:-/tmp/fan-curve-demo}
image=swift:6.1-jammy

rm -rf "$demo"
mkdir -p "$demo"

docker run --rm -v "$root":/src -w /src "$image" bash -lc \
  'swift build -c release --product fan-curve-curve --static-swift-stdlib 2>&1 | tail -2'

docker run --rm -v "$root":/src -w /src "$image" \
  bash -lc 'cat .build/release/fan-curve-curve' > "$demo/fan-curve-curve"
chmod +x "$demo/fan-curve-curve"

"$demo/fan-curve-curve" --step 50 >/dev/null
echo "fan-curve-curve ready in $demo"
