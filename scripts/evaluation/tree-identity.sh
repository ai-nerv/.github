#!/usr/bin/env bash

tree_identity() (
    cd -- "$1" || exit 1
    find . -type d -print0 | LC_ALL=C sort -z || exit 1
    printf '\0FILES\0'
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum --
)
