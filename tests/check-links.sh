#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# check-links.sh: every link in the documentation resolves.
#
#   - a relative link must name a file or directory that exists;
#   - a link with #anchor (to another page or to the same page) must name
#     a heading of that page, as GitHub turns headings into anchors;
#   - with CHECK_EXTERNAL=1, every http(s) link must also answer (curl).
#
# usage: sh tests/check-links.sh [FILE.md ...]
#   default: every .md file in the repository
# Run it from the repository root. Exit 0 on pass, 1 on any failure.

set -u
fail=0
n=0

if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046 # word splitting wanted: the file names have no spaces
    set -- $(find . -name '*.md' -not -path './.git/*' | sed 's|^\./||' | sort)
fi

# anchors FILE: the GitHub anchor of every heading in FILE, one per line
# (lowercase; drop everything but letters, digits, space, - and _;
# spaces become hyphens; a repeated anchor gets -1, -2, ...).
anchors() {
    awk '
        /^```/ { fence = !fence; next }
        fence { next }
        /^#+[ \t]/ {
            h = $0
            sub(/^#+[ \t]+/, "", h); sub(/[ \t]+#*[ \t]*$/, "", h)
            h = tolower(h)
            gsub(/[^a-z0-9 _-]/, "", h)
            gsub(/ /, "-", h)
            if (h in seen) { seen[h]++; print h "-" seen[h] - 1 }
            else { seen[h] = 1; print h }
        }
        /<a (name|id)="[^"]+"/ {
            s = $0; sub(/.*<a (name|id)="/, "", s); sub(/".*/, "", s); print s
        }
    ' "$1"
}

for f in "$@"; do
    [ -f "$f" ] || { echo "FAIL: no such file $f"; fail=1; continue; }
    dir=$(dirname -- "$f")
    # targets of ](target) outside code fences and inline code
    targets=$(awk '
        /^```/ { fence = !fence; next }
        fence { next }
        { gsub(/`[^`]*`/, ""); print }
    ' "$f" | grep -oE '\]\([^) ]+\)' | sed 's/^](\(.*\))$/\1/' | sort -u)
    for t in $targets; do
        n=$((n + 1))
        case $t in
            mailto:*) continue ;;
            http://*|https://*)
                if [ "${CHECK_EXTERNAL:-0}" = 1 ]; then
                    if ! curl -sfL -o /dev/null --max-time 30 -- "$t"; then
                        echo "FAIL: $f links to $t, which does not answer"
                        fail=1
                    fi
                fi
                continue ;;
        esac
        path=${t%%#*}
        case $t in *'#'*) anchor=${t#*#} ;; *) anchor= ;; esac
        if [ -n "$path" ]; then
            target=$dir/$path
            if [ ! -e "$target" ]; then
                echo "FAIL: $f links to $t, which does not exist"
                fail=1
                continue
            fi
        else
            target=$f
        fi
        if [ -n "$anchor" ]; then
            if [ ! -f "$target" ] || ! anchors "$target" | grep -qxF -- "$anchor"; then
                echo "FAIL: $f links to $t, and $target has no heading #$anchor"
                fail=1
            fi
        fi
    done
done

if [ "$fail" -eq 0 ]; then
    echo "check-links: $n links in $# files resolve"
fi
exit "$fail"
