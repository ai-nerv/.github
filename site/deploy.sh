#!/bin/sh
# Publish docs/ to ai-nerv/ai-nerv.github.io, the repository GitHub serves ai-nerv.com from. That
# repository holds only this output: a fresh clone, replaced wholesale, one commit naming its source.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
target=${SITE_REPO:-https://github.com/ai-nerv/ai-nerv.github.io.git}

if [ -n "$(git -C "$root" status --porcelain -- site docs)" ]; then
  echo "deploy: commit site/ and docs/ first, so the deploy names a source that exists" >&2
  exit 1
fi

node "$root/site/build.mjs"
if [ -n "$(git -C "$root" status --porcelain -- docs)" ]; then
  echo "deploy: docs/ is not what site/ builds; build and commit it first" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
git clone -q --depth 1 "$target" "$work/out"

# Everything but the history goes, so a page removed from site/ is removed from the site.
find "$work/out" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$root/docs/." "$work/out/"
printf '%s\n' '# ai-nerv.com' '' \
  'Generated. The source is `site/` in [ai-nerv/.github](https://github.com/ai-nerv/.github);' \
  'edit it there and run `site/deploy.sh`. Nothing here is edited by hand.' >"$work/out/README.md"

source=$(git -C "$root" rev-parse --short HEAD)
cd "$work/out"
git add -A
if git diff --cached --quiet; then
  echo "deploy: nothing changed"
  exit 0
fi
git commit -q -m "chore(site): deploy $source"
git push -q origin HEAD
echo "deploy: $source published"
