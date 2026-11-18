#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
APP="${1:?Specify an absolute application path}"
RES="$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
test -x "$APP/Contents/MacOS/$EXECUTABLE"
sparkle="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
for binary in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater \
    XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    test -x "$sparkle/$binary"
done

for notice in Sparkle-LICENSE.txt FFmpeg-COPYING.GPLv3.txt ThirdPartyNotices.txt VMAF-LICENSE.txt; do
    cmp "VMAF/Resources/$notice" "$RES/$notice"
done

for model in vmaf_v0.6.1.json vmaf_4k_v0.6.1.json; do
    cmp "VMAF/Resources/Models/$model" "$RES/$model"
done

while IFS= read -r -d '' binary; do
    file -b "$binary" | grep -q 'Mach-O' || continue
    case "$binary" in "$RES/ffmpeg"|"$RES/ffmpeg.x86_64") continue ;; esac
    architectures=" $(lipo -archs "$binary") "
    if [[ "$architectures" != *" arm64 "* || "$architectures" != *" x86_64 "* ]]; then
        echo "Expected a universal Mach-O in the app: $binary" >&2
        exit 1
    fi
done < <(find "$APP" -type f -print0)

test -x "$RES/ffmpeg" && test -x "$RES/ffmpeg.x86_64"
echo "ffmpeg:        $(lipo -archs "$RES/ffmpeg")"
echo "ffmpeg.x86_64: $(lipo -archs "$RES/ffmpeg.x86_64")"
[ "$(lipo -archs "$RES/ffmpeg")" = "arm64" ] || { echo "bundled arm64 helper is missing or not thin arm64"; exit 1; }
[ "$(lipo -archs "$RES/ffmpeg.x86_64")" = "x86_64" ] || { echo "Intel helper is missing or not thin x86_64"; exit 1; }
# Pinned checksums come from the engine provenance doc.
doc=docs/ENGINE_PROVENANCE.md
arm_sha=$(grep -F '`VMAF/Resources/ffmpeg` |' "$doc" | awk -F'|' '{gsub(/[` ]/, "", $6); print $6}')
intel_sha=$(grep -F '`VMAF/Resources/ffmpeg.x86_64` |' "$doc" | awk -F'|' '{gsub(/[` ]/, "", $6); print $6}')
[ "$(shasum -a 256 "$RES/ffmpeg" | awk '{print $1}')" = "$arm_sha" ] || { echo "arm64 helper content does not match the pinned SHA-256"; exit 1; }
[ "$(shasum -a 256 "$RES/ffmpeg.x86_64" | awk '{print $1}')" = "$intel_sha" ] || { echo "Intel helper content does not match the pinned SHA-256"; exit 1; }

for helper in "$RES/ffmpeg" "$RES/ffmpeg.x86_64"; do
  codesign --verify --strict "$helper" || { echo "signature invalid: $helper"; exit 1; }
  INFO="$(codesign -dvv "$helper" 2>&1)" || { echo "cannot read signature: $helper"; exit 1; }
  case "$INFO" in *'TeamIdentifier=KU3N25YGLU'*) ;; *) echo "helper not signed by the pinned Developer ID team: $helper"; exit 1 ;; esac
done

# Bundle paths contain spaces, so stage model + log under a clean tmp dir.
test -f Fixtures/vmaf-reference.mp4 && test -f Fixtures/vmaf-comparison.mp4
SANDBOX="$(mktemp -d)"
trap 'rm -rf -- "$SANDBOX"' EXIT
cp "$RES/vmaf_v0.6.1.json" "$SANDBOX/model.json"
HOST_ARCH="$(uname -m)"
verify_helper() { # $1 = helper slice (arm64|x86_64), $2 = helper path
  local slice="$1" helper="$2"
  if [[ "$slice" != "$HOST_ARCH" ]] &&
    ! { [[ "$HOST_ARCH" == arm64 && "$slice" == x86_64 ]] && arch -x86_64 /usr/bin/true 2>/dev/null; }; then
    if [[ "${REQUIRE_BOTH_ENGINE_SLICES:-0}" == 1 ]]; then
      echo "Cannot execute the required $slice engine fixture on $HOST_ARCH." >&2
      return 1
    fi
    echo "Skipping $slice execution on $HOST_ARCH. Signature and architecture verified."
    return 0
  fi
  local ver; ver="$(arch "-$slice" "$helper" -hide_banner -version 2>&1)" || { echo "$slice helper failed -version probe"; exit 1; }
  case "$ver" in *'ffmpeg version 9.0.2'*) ;; *) echo "$slice helper reports unexpected version: $ver"; exit 1 ;; esac
  local filters; filters="$(arch "-$slice" "$helper" -hide_banner -filters 2>&1)" || { echo "$slice helper failed -filters probe"; exit 1; }
  case "$filters" in *libvmaf*) ;; *) echo "$slice helper lacks libvmaf"; exit 1 ;; esac
  local out="$SANDBOX/$slice.json"
  arch "-$slice" "$helper" -y -hide_banner -loglevel error \
    -i Fixtures/vmaf-reference.mp4 -i Fixtures/vmaf-comparison.mp4 \
    -lavfi "[1:v]setpts=PTS-STARTPTS[dist];[0:v]setpts=PTS-STARTPTS[ref];[dist][ref]libvmaf=model=path=$SANDBOX/model.json:log_fmt=json:log_path=$out:n_threads=4" \
    -f null - || { echo "$slice helper failed the fixture analysis"; exit 1; }
  python3 - "$out" "$slice" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
v = d["pooled_metrics"]["vmaf"]
frames = d["frames"]
assert len(frames) == 24, f"[{sys.argv[2]}] expected 24 scored frames, got {len(frames)}"
assert abs(v["mean"] - 33.08) < 0.5, f"[{sys.argv[2]}] mean VMAF {v['mean']} deviates from the pinned 33.08"
assert "integer_motion2" in frames[0]["metrics"], "expected libvmaf 3.x feature identities"
assert "integer_motion" not in frames[0]["metrics"], "legacy identity should be absent on 3.x"
assert d.get("version") == "3.2.0", f"unexpected libvmaf version {d.get('version')}"
print(f"[{sys.argv[2]}] VMAF mean {v['mean']:.2f} over {len(frames)} frames")
PY
}
verify_helper arm64 "$RES/ffmpeg"
verify_helper x86_64 "$RES/ffmpeg.x86_64"
echo "Engine verification passed for the available runtime architectures."
