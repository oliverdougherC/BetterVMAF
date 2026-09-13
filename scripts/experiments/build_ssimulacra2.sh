#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
# This research build intentionally uses declared Homebrew build dependencies.
root=${1:?Supply external corpus root}
repo=$(cd "$(dirname "$0")/../.." && pwd)
src="$root/upstream/libjxl"
revision=a7a9c787341cf703dede03c2009fa460cae5e5df
if [[ ! -d "$src/.git" ]]; then git clone --depth 1 --branch v0.12.0 https://github.com/libjxl/libjxl.git "$src"; fi
[[ $(git -C "$src" rev-parse HEAD) == "$revision" ]] || { echo "Checkout libjxl $revision first" >&2; exit 1; }
cp "$repo/scripts/experiments/ssimulacra2_linear.cc" "$src/tools/ssimulacra2_linear.cc"
if ! rg -q 'add_executable\(ssimulacra2_linear' "$src/tools/CMakeLists.txt"; then
cat >> "$src/tools/CMakeLists.txt" <<'CMAKE'
add_executable(ssimulacra2_linear ssimulacra2_linear.cc ssimulacra2.cc)
target_link_libraries(ssimulacra2_linear jxl_gauss_blur jxl_extras-internal jxl_tool)
CMAKE
fi
cmake -S "$src" -B "$src/build" -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_DEVTOOLS=ON -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_ENABLE_JNI=OFF -DJPEGXL_ENABLE_SJPEG=OFF -DJPEGXL_ENABLE_SKCMS=OFF -DJPEGXL_FORCE_SYSTEM_BROTLI=ON -DJPEGXL_FORCE_SYSTEM_LCMS2=ON -DJPEGXL_FORCE_SYSTEM_HWY=ON -DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_DOXYGEN=OFF
cmake --build "$src/build" --target ssimulacra2 ssimulacra2_linear -j 4
