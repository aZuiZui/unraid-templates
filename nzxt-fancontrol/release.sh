#!/bin/bash
# One-command release: picks the next version, adds the changelog entry, builds the .plg,
# commits, pushes to GitHub (origin) and Gitea (gitea, if set up), and optionally installs on the NAS.
# Usage: ./release.sh [--deploy] "change" ["change" ...]
set -euo pipefail
cd "$(dirname "$0")"
NAS=${NAS:-root@192.168.0.10}

deploy=""
[[ ${1:-} == --deploy ]] && { deploy=1; shift; }
(( $# )) || { echo 'usage: ./release.sh [--deploy] "change" ["change" ...]'; exit 1; }
[[ -z $(git status --porcelain -- . ':!CHANGES.md' ':!nzxt-fancontrol.plg') ]] ||
  { echo "commit or stash your source changes first:"; git status --short -- .; exit 1; }

# Today's date, with a letter suffix for further releases on the same day (Unraid compares versions as strings).
today=$(date +%Y.%m.%d)
last=$(sed -n 's/^###\([^ ]*\).*/\1/p' CHANGES.md | head -n1)
if [[ $last == "$today"* ]]; then
  suffix=${last#"$today"}
  [[ $suffix == z ]] && { echo "out of letters for $today"; exit 1; }
  version=$today$( [[ -z $suffix ]] && echo a || echo "$suffix" | tr 'a-y' 'b-z' )
else
  version=$today
fi

{ echo "###$version"; printf -- '- %s\n' "$@"; echo; cat CHANGES.md; } > CHANGES.md.new && mv CHANGES.md.new CHANGES.md
./build.sh "$version"

git add -- .
trailer=()
[[ -n ${RELEASE_TRAILER:-} ]] && trailer=(-m "$RELEASE_TRAILER")
git commit -q -m "nzxt-fancontrol v$version" -m "$(printf -- '- %s\n' "$@")" "${trailer[@]}"
git push -q origin HEAD:main
git remote get-url gitea >/dev/null 2>&1 && git push -q gitea HEAD:main
echo "released v$version"

if [[ -n $deploy ]]; then
  scp -q nzxt-fancontrol.plg "$NAS:/tmp/nzxt-fancontrol.plg"
  ssh "$NAS" 'plugin install /tmp/nzxt-fancontrol.plg forced 2>&1 | grep -E "installed|rror"; rm -f /tmp/nzxt-fancontrol.plg'
fi
