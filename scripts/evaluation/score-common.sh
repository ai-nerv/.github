#!/usr/bin/env bash

score_attempt_limit() {
    local input=$1 scratch=$2 limit=64
    if [[ -e $input/provider-attempt-limit.txt || -L $input/provider-attempt-limit.txt ]]; then
        "$helper" file "$input" provider-attempt-limit.txt "$scratch/attempt-limit" 3 1 >/dev/null || return 1
        IFS= read -r limit < "$scratch/attempt-limit/input" || return 1
        [[ $limit =~ ^[1-9][0-9]?$ && $limit -le 64 && $(wc -c < "$scratch/attempt-limit/input") == $((${#limit}+1)) ]] || return 1
    fi
    printf '%s\n' "$limit"
}
