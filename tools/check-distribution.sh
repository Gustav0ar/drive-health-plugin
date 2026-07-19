#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

plugin_dir=drive-health
manifest="$plugin_dir/plugin.toml"
catalog=catalog.toml
failed=$(mktemp "${TMPDIR:-/tmp}/drive-health-distribution.XXXXXX")
text_files=$(mktemp "${TMPDIR:-/tmp}/drive-health-text-files.XXXXXX")
trap 'rm -f -- "$failed" "$text_files"' EXIT HUP INT TERM
: >"$failed"

report() {
  category=$1
  path=$2
  line=${3:-0}
  printf '%s:%s:%s\n' "$category" "$path" "$line" >&2
  printf 'failed\n' >"$failed"
}

for required in \
  catalog.toml README.md LICENSE \
  "$plugin_dir/plugin.toml" "$plugin_dir/README.md" \
  "$plugin_dir/thumbnail.webp" \
  "$plugin_dir/collector.luau" "$plugin_dir/service.luau" \
  "$plugin_dir/history.luau" "$plugin_dir/widget.luau" "$plugin_dir/panel.luau" \
  "$plugin_dir/translations/en.json" "$plugin_dir/scripts/collect_raw.sh"; do
  if ! git ls-files --error-unmatch "$required" >/dev/null 2>&1; then
    report source-layout "$required"
  fi
done

collector_count=$(git ls-files | awk '/(^|\/)collector\.luau$/ { count++ } END { print count + 0 }')
if [ "$collector_count" -ne 1 ]; then
  report duplicate-implementation collector.luau
fi

if [ ! -f "$catalog" ] || [ ! -f "$manifest" ]; then
  report source-layout "$catalog/$manifest"
else
  field_value() {
    field=$1
    file=$2
    sed -n "s/^[[:space:]]*${field}[[:space:]]*=[[:space:]]*//p" "$file" | sed -n '1p'
  }

  for field in id name version plugin_api author license deprecated icon description tags dependencies; do
    catalog_value=$(field_value "$field" "$catalog")
    manifest_value=$(field_value "$field" "$manifest")
    if [ -z "$catalog_value" ] || [ "$catalog_value" != "$manifest_value" ]; then
      report catalog-manifest-parity "$field"
    fi
  done

  plugin_id=$(field_value id "$manifest" | sed 's/^"//; s/"$//')
  plugin_suffix=${plugin_id#*/}
  if [ "$plugin_id" != "gustav0ar/drive-health" ] || [ "$plugin_suffix" != "$plugin_dir" ]; then
    report plugin-identity "$manifest"
  fi

  collector_version=$(sed -n 's/^local EXPECTED_COLLECTOR_VERSION = "\([^"]*\)"$/\1/p' \
    "$plugin_dir/collector.luau")
  raw_collector_version=$(sed -n 's/^collector_version="\([^"]*\)"$/\1/p' \
    "$plugin_dir/scripts/collect_raw.sh")
  if [ -z "$collector_version" ] || [ -z "$raw_collector_version" ] \
    || [ "$collector_version" != "$raw_collector_version" ]; then
    report collector-version-parity "$plugin_dir/scripts/collect_raw.sh"
  fi
fi

git ls-files | while IFS= read -r path; do
  case "$path" in
    plans/*|*/plans/*|*.log|*.cache|*.tmp|*.swp|*.swo|*~|.DS_Store|*/.DS_Store|\
    .idea/*|*/.idea/*|.vscode/*|*/.vscode/*|__pycache__/*|*/__pycache__/*|\
    .pytest_cache/*|*/.pytest_cache/*|.cache/*|*/.cache/*|node_modules/*|*/node_modules/*|\
    build/*|*/build/*|dist/*|*/dist/*|target/*|*/target/*|.venv/*|*/.venv/*|\
    .env|*/.env|.env.*|*/.env.*|raw.json|*/raw.json|smart.json|*/smart.json|\
    alerts.json|*/alerts.json|history.json|*/history.json|preferences.json|*/preferences.json|\
    state.json|*/state.json|snapshot.json|*/snapshot.json|snapshot-*.json|*/snapshot-*.json|\
    *.snapshot.json|*.cache.json)
      report tracked-artifact "$path"
      ;;
  esac
done

git grep -I -l -e '' -- . >"$text_files" || true
while IFS= read -r path; do
  [ -f "$path" ] || continue
  if ! awk -v path="$path" '
    function flag(category) {
      print category ":" path ":" FNR > "/dev/stderr"
      found = 1
    }
    function check_home(line, prefix,    rest, owner) {
      rest = line
      while (match(rest, prefix "[[:alnum:]_.-]+")) {
        owner = substr(rest, RSTART + length(prefix), RLENGTH - length(prefix))
        if (owner != "example" && owner != "user" && owner != "tester") {
          flag("absolute-home-path")
        }
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    {
      lower = tolower($0)
      check_home($0, "/home/")
      check_home($0, "/Users/")

      if ($0 ~ /BEGIN[[:space:]][A-Z0-9 ]*PRIVATE KEY/) {
        flag("private-key-header")
      }

      credential = "(password|passwd|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)"
      if (match(lower, credential "[[:space:]]*[:=][[:space:]]*")) {
        rest = substr($0, RSTART + RLENGTH)
        first = substr(rest, 1, 1)
        next_character = substr(rest, 2, 1)
        quote = sprintf("%c", 39)
        if ((first == "\"" || first == quote) \
            && next_character != "" && next_character !~ /[$<{]/) {
          flag("literal-credential-assignment")
        } else if (first ~ /[[:alnum:]_.\/-]/) {
          flag("literal-credential-assignment")
        }
      }
    }
    END { exit found ? 1 : 0 }
  ' "$path"; then
    printf 'failed\n' >"$failed"
  fi
done <"$text_files"

if [ -s "$failed" ]; then
  echo "distribution check failed; only category, path, and line are reported" >&2
  exit 1
fi

echo "distribution checks passed"
