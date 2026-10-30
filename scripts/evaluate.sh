#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
exec "${NERV_BASH:-bash}" "$root/scripts/evaluation/run-suite.sh" "$@"
