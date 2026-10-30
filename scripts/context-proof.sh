#!/usr/bin/env bash
set -euo pipefail
anchor=${NERV_TEST_ANCHOR:-}
host=${NERV_HOST_TMP_ID:-}
[[ -n $anchor && -n $host && -d $anchor && ! -L $anchor ]] || {
    echo 'verification requires the private test context; use oslo make' >&2; exit 1;
}
actual=$(stat -Lc '%d:%i' /var/tmp)
expected=$(stat -Lc '%d:%i' "$anchor")
[[ $(id -u) == 0 && $(stat -Lc '%u:%a' /var/tmp) == 0:1777 &&
   $actual == "$expected" && $actual != "$host" ]] || {
    echo 'verification registry anchor is not privately mounted' >&2; exit 1;
}
for directory in / /home /var; do
    [[ $(stat -Lc %u "$directory") == 0 ]] || {
        echo 'verification ancestor ownership is not namespace-local' >&2; exit 1;
    }
done
[[ $(stat -Lc '%u:%a' /tmp) == 0:1777 ]] || {
    echo 'verification temporary root is not private and namespace-owned' >&2; exit 1;
}
jq -n --arg actual "$actual" --arg host "$host" \
    '{kind:"private-var-tmp",uid:0,anchor:$actual,host_anchor:$host,private_tmp:true,owned_ancestors:true}'
