#!/usr/bin/env bash

preserve_binary() {
    local source=$1 destination=$2 manifest=$3 expected actual
    [[ -f $source && -x $source && ! -e $destination && ! -L $destination ]] || {
        echo 'invalid executable snapshot source or destination' >&2; return 1;
    }
    expected=$(sha256sum < "$source") || return 1
    expected=${expected%% *}
    cp --reflink=auto -- "$source" "$destination" || return 1
    chmod 555 "$destination" || return 1
    actual=$(sha256sum < "$destination") || return 1
    actual=${actual%% *}
    [[ $actual == "$expected" ]] || { echo 'executable changed while copying' >&2; return 1; }
    sha256sum "$destination" >> "$manifest" || return 1
    printf '%s\n' "$actual"
}

verify_preserved_binaries() {
    local manifest=$1
    if [[ ! -s $manifest ]] || ! sha256sum -c "$manifest"; then
        echo 'selected artifact integrity failed' >&2
        return 1
    fi
}
