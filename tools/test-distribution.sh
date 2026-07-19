#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/drive-health-distribution-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM

mkdir -p "$fixture/tools" "$fixture/drive-health/scripts" \
  "$fixture/drive-health/translations"
cp "$repo_root/tools/check-distribution.sh" "$fixture/tools/check-distribution.sh"
cp "$repo_root/catalog.toml" "$fixture/catalog.toml"
cp "$repo_root/README.md" "$fixture/README.md"
cp "$repo_root/LICENSE" "$fixture/LICENSE"
cp "$repo_root/drive-health/plugin.toml" "$fixture/drive-health/plugin.toml"
cp "$repo_root/drive-health/README.md" "$fixture/drive-health/README.md"
cp "$repo_root/drive-health/thumbnail.webp" "$fixture/drive-health/thumbnail.webp"
cp "$repo_root/drive-health/collector.luau" "$fixture/drive-health/collector.luau"
for file in service.luau history.luau widget.luau panel.luau; do
  cp "$repo_root/drive-health/$file" "$fixture/drive-health/$file"
done
cp "$repo_root/drive-health/translations/en.json" \
  "$fixture/drive-health/translations/en.json"
cp "$repo_root/drive-health/scripts/collect_raw.sh" \
  "$fixture/drive-health/scripts/collect_raw.sh"

git -C "$fixture" init -q
git -C "$fixture" add .
(cd "$fixture" && sh tools/check-distribution.sh) >/dev/null

printf '{}\n' >"$fixture/snapshot.json"
git -C "$fixture" add snapshot.json
if (cd "$fixture" && sh tools/check-distribution.sh) >"$fixture/output" 2>&1; then
  echo "distribution check accepted a tracked runtime snapshot" >&2
  exit 1
fi
grep -qx 'tracked-artifact:snapshot.json:0' "$fixture/output"
git -C "$fixture" rm -q --cached snapshot.json
rm -f -- "$fixture/snapshot.json" "$fixture/output"

printf '%s%s%s\n' '/home/' 'distribution-fixture' '/project' >"$fixture/home-path.txt"
git -C "$fixture" add home-path.txt
if (cd "$fixture" && sh tools/check-distribution.sh) >"$fixture/output" 2>&1; then
  echo "distribution check accepted a non-generic home path" >&2
  exit 1
fi
grep -qx 'absolute-home-path:home-path.txt:1' "$fixture/output"
if grep -q 'distribution-fixture' "$fixture/output"; then
  echo "distribution check printed matched private content" >&2
  exit 1
fi
git -C "$fixture" rm -q --cached home-path.txt
rm -f -- "$fixture/home-path.txt" "$fixture/output"

printf '%s%s%s\n' 'access_' 'token=' 'fixture-value' >"$fixture/credential.txt"
git -C "$fixture" add credential.txt
if (cd "$fixture" && sh tools/check-distribution.sh) >"$fixture/output" 2>&1; then
  echo "distribution check accepted a literal credential assignment" >&2
  exit 1
fi
grep -qx 'literal-credential-assignment:credential.txt:1' "$fixture/output"
if grep -q 'fixture-value' "$fixture/output"; then
  echo "distribution check printed matched credential content" >&2
  exit 1
fi
git -C "$fixture" rm -q --cached credential.txt
rm -f -- "$fixture/credential.txt" "$fixture/output"

awk '
  /^collector_version=/ { print "collector_version=\"0.9.9\""; next }
  { print }
' "$fixture/drive-health/scripts/collect_raw.sh" >"$fixture/collect_raw.next"
mv "$fixture/collect_raw.next" "$fixture/drive-health/scripts/collect_raw.sh"
git -C "$fixture" add drive-health/scripts/collect_raw.sh
if (cd "$fixture" && sh tools/check-distribution.sh) >"$fixture/output" 2>&1; then
  echo "distribution check accepted mismatched collector versions" >&2
  exit 1
fi
grep -qx \
  'collector-version-parity:drive-health/scripts/collect_raw.sh:0' \
  "$fixture/output"

echo "distribution negative tests passed"
