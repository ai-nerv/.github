#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/with spaces"
source_binary="$scratch/original"
snapshot="$scratch/with spaces/selected"
manifest="$scratch/manifest"
printf '#!/bin/sh\nprintf original\n' > "$source_binary"
chmod 755 "$source_binary"
digest=$(preserve_binary "$source_binary" "$snapshot" "$manifest")
[[ $digest == "$(sha256sum < "$source_binary" | cut -d' ' -f1)" ]]
[[ $(stat -c %a "$snapshot") == 555 ]]
printf '#!/bin/sh\nprintf replaced\n' > "$source_binary"
[[ $("$snapshot") == original && $("$source_binary") == replaced ]]
verify_preserved_binaries "$manifest"
if preserve_binary "$source_binary" "$snapshot" "$manifest"; then exit 1; fi
ln -s "$source_binary" "$scratch/link"
if preserve_binary "$source_binary" "$scratch/link" "$manifest"; then exit 1; fi
if preserve_binary "$scratch/missing" "$scratch/new" "$manifest"; then exit 1; fi
chmod u+w "$snapshot"
printf '\n# corruption\n' >> "$snapshot"
if verify_preserved_binaries "$manifest"; then exit 1; fi
rm -- "$snapshot"
if verify_preserved_binaries "$manifest"; then exit 1; fi
touch "$scratch/empty"
if verify_preserved_binaries "$scratch/empty"; then exit 1; fi
echo 'preserved binaries: retained bytes, private mode, spaces and invalidation PASS'
