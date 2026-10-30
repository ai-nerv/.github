#!/runner/bin/bash
set -euo pipefail
if [[ ( $# == 2 || ( $# == 3 && $3 == --event-bootstrap ) ) && $1 == ask && $2 == --json ]]; then
    exec /runner/bin/eval-world record ask "$XDG_RUNTIME_DIR/model-ipc" /family/members/melchior/input "$@"
fi
exec /family/members/melchior/input "$@"
