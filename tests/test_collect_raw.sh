#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_bin="$project_dir/tests/fixtures/bin"

payload=$(PATH="$fixture_bin:$PATH" sh "$project_dir/scripts/collect_raw.sh")
printf '%s\n' "$payload" | jq -e '
  .schema == 2
  and .collector_version == "0.6.0"
  and (.lsblk.blockdevices | length) == 2
  and (.smart | length) == 2
  and ([.smart[].requested_device] | sort) == ["/dev/nvme0", "/dev/sda"]
  and (.smart[] | select(.requested_device == "/dev/sda") | .payload.test_standby) == true
  and (.smart[] | select(.requested_device == "/dev/nvme0") | .payload.test_standby) == false
  and ([.smart[].exit_code] | all(. == 0))
' >/dev/null

empty_payload=$(SMARTCTL_EMPTY=1 PATH="$fixture_bin:$PATH" sh "$project_dir/scripts/collect_raw.sh")
printf '%s\n' "$empty_payload" | jq -e '
  (.smart | length) == 2
  and (.smart[] | select(.requested_device == "/dev/sda") | .exit_code) == 2
  and (.smart[] | select(.requested_device == "/dev/sda")
    | .payload.smartctl.messages[0].string) == "smartctl produced no JSON output"
' >/dev/null

output=$(mktemp "${TMPDIR:-/tmp}/noctalia-smart-raw-test.XXXXXX")
PATH="$fixture_bin:$PATH" sh "$project_dir/scripts/collect_raw.sh" --output "$output"
jq -e '.schema == 2 and (.smart | length) == 2' "$output" >/dev/null
rm -f -- "$output"

echo "raw collector tests passed"
