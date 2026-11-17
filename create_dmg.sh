#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
version=$(python3 "$root/scripts/release/release.py" version)
exec "$root/scripts/release/package.sh" dry-run "${1:-$root/build/packages/$version}"
