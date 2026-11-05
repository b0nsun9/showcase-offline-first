#!/bin/sh
set -eu
src="$(dirname "$0")/../Packages/Domain/Sources"
bad=$(grep -rnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$src" | grep -vE 'import[[:space:]]+Foundation[[:space:]]*$' || true)
bad="$bad$(grep -rn 'URLSession' "$src" || true)"
[ -z "$bad" ] || { echo "Domain may import only Foundation:"; echo "$bad"; exit 1; }
