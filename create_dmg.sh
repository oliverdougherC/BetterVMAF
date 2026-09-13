#!/bin/bash
set -euo pipefail
# Local ad-hoc signing, native engine validation and corresponding-source bundle.
# No Developer ID account or notarization is implied.
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${REPO_ROOT}/scripts/package/build_release.py" "$@"
