-- Behavioral tests for the isolated alert service.

local state = {}
local watchers = {}
local notifications = {}
local stateWrites = {}
local stateRenames = {}

local function translate(key, substitutions)
  local value = key
  for name, replacement in pairs(substitutions or {}) do
    value = value:gsub("{" .. name .. "}", tostring(replacement))
  end
  return value
end

noctalia = {
  getConfig = function(key)
    local values = {
      alerts_enabled = true,
      notify_recovery = true,
      warning_temperature = 65,
      critical_temperature = 80,
      life_warning_percent = 20,
      show_hdd = false,
      alert_hdd = true,
      drive_missing_alerts = true,
      missing_grace_scans = 3,
      use_hotspot_temperature = true,
    }
    return values[key]
  end,
  pluginDataDir = function() return "/mock/plugin-data" end,
  readFile = function(_path) return nil end,
  writeFile = function(path, _contents) table.insert(stateWrites, path) return true end,
  renameFile = function(from, to) table.insert(stateRenames, { from = from, to = to }) return true end,
  log = function(_message) end,
  notify = function(title, body)
    table.insert(notifications, { severity = "warning", title = title, body = body })
  end,
  notifyError = function(title, body)
    table.insert(notifications, { severity = "critical", title = title, body = body })
  end,
  tr = translate,
  state = {
    get = function(key) return state[key] end,
    set = function(key, value) state[key] = value end,
    watch = function(key, callback) watchers[key] = callback end,
  },
  json = {
    decode = function(_raw) return nil end,
    encode = function(_value, _pretty) return "{}" end,
  },
}

local handle = assert(io.open("service.luau", "rb"))
local source = handle:read("*a")
handle:close()
source = source:gsub("([%a_][%w_]*) %+%= ([^\n]+)", "%1 = %1 + %2")
assert(load(source, "@service.luau"))()

local publishSnapshot = assert(watchers.collector_snapshot, "alert service did not watch collector snapshots")
local function publish(value)
  state.collector_snapshot = value
  publishSnapshot(value)
end
local dismiss = assert(watchers.dismiss_alert_request, "alert service did not watch dismissal requests")
local function drive(temperature)
  return {
    id = "SERIAL1", device = "/dev/nvme0n1", model = "Fixture SSD",
    kind = "ssd", health = "passed", smart_available = true,
    temperature_c = temperature, hotspot_temperature_c = temperature, remaining_life_percent = 95,
    available_spare_percent = 100, critical_warning = 0,
    media_errors = 0, reallocated_sectors = 0, pending_sectors = 0,
    uncorrectable_errors = 0, unsafe_shutdowns = 12, error_log_entries = 5893,
    smart_completeness = "full", alerts_enabled = true, presence_alert_enabled = true,
    self_test_state = "passed",
  }
end

local function snapshot(disk, collectionId)
  return {
    collection_id = collectionId,
    disks = disk ~= nil and { disk } or {},
    dependencies = { ready = true, missing = {}, missing_text = "", signature = "" },
    summary = { ssd_count = disk ~= nil and 1 or 0 },
  }
end

local function findIssue(kind)
  for _, issue in ipairs(state.snapshot.issues or {}) do
    if issue.kind == kind then
      return issue
    end
  end
  return nil
end

publish(snapshot(drive(45)))
assert(#state.snapshot.issues == 0, "healthy drive produced an alert")
assert(#notifications == 0, "healthy drive produced a notification")

publish(snapshot(drive(70)))
assert(#state.snapshot.issues == 1 and state.snapshot.issues[1].kind == "temperature", "warning temperature was missed")
assert(#notifications == 1 and notifications[1].severity == "warning", "warning notification was not sent")

publish(snapshot(drive(70)))
assert(#notifications == 1, "unchanged warning notification was duplicated")

publish(snapshot(drive(63)))
assert(#state.snapshot.issues == 1 and state.snapshot.issues[1].message == "alerts.temperature_cooling",
  "temperature hysteresis displayed a contradictory threshold message")
assert(#notifications == 1, "cooling hysteresis duplicated its warning notification")

dismiss({ id = "SERIAL1:temperature", nonce = 1 })
assert(#state.snapshot.issues == 0 and state.snapshot.summary.dismissed_alert_count == 1,
  "individual dismissal did not hide the active issue")
assert(#notifications == 1, "dismissing an issue emitted a notification")

publish(snapshot(drive(63)))
assert(#state.snapshot.issues == 0 and state.snapshot.summary.dismissed_alert_count == 1,
  "dismissal did not persist across an unchanged scan")
assert(#notifications == 1, "dismissed issue duplicated its notification")

publish(snapshot(drive(85)))
assert(state.snapshot.issues[1].severity == "critical", "critical escalation was missed")
assert(state.snapshot.summary.dismissed_alert_count == 0, "critical escalation stayed dismissed")
assert(#notifications == 2 and notifications[2].severity == "critical", "critical escalation did not notify")

publish(snapshot(drive(60)))
assert(#state.snapshot.issues == 0, "temperature recovery did not clear")
assert(#notifications == 3 and notifications[3].severity == "warning", "recovery did not notify")

publish(snapshot(drive(70)))
assert(#notifications == 4, "recurring temperature issue did not notify")
dismiss({ id = "SERIAL1:temperature", nonce = 2 })
publish(snapshot(drive(45)))
assert(state.snapshot.summary.dismissed_alert_count == 0, "resolved issue left a stale dismissal")
assert(#notifications == 4, "dismissed issue emitted an unwanted recovery notification")
publish(snapshot(drive(70)))
assert(#state.snapshot.issues == 1 and #notifications == 5,
  "issue recurrence after resolution remained dismissed")
dismiss({ id = "SERIAL1:temperature", nonce = 3 })
dismiss({ restore_all = true, nonce = 4 })
assert(#state.snapshot.issues == 1 and state.snapshot.summary.dismissed_alert_count == 0,
  "restoring dismissals did not reveal the active issue")
assert(#notifications == 5, "restoring an issue duplicated its notification")
publish(snapshot(drive(45)))

local multiple = drive(70)
multiple.interface_crc_errors = 2
publish(snapshot(multiple))
assert(#state.snapshot.issues == 2, "multi-alert fixture did not produce two issues")
dismiss({ all = true, nonce = 5 })
assert(#state.snapshot.issues == 0 and state.snapshot.summary.dismissed_alert_count == 2,
  "dismiss all did not hide every active issue")
dismiss({ restore_all = true, nonce = 6 })
assert(#state.snapshot.issues == 2 and state.snapshot.summary.dismissed_alert_count == 0,
  "restore dismissed did not reveal all issues")
publish(snapshot(drive(45)))

local hddIssue = drive(35)
hddIssue.kind = "hdd"
hddIssue.remaining_life_percent = nil
hddIssue.interface_crc_errors = 2
publish(snapshot(hddIssue))
assert(#state.snapshot.issues == 1 and state.snapshot.issues[1].kind == "interface-crc",
  "HDD interface integrity alert was missed")
hddIssue.interface_crc_errors = 0
publish(snapshot(hddIssue))

local hotspot = drive(45)
hotspot.hotspot_temperature_c = 70
publish(snapshot(hotspot))
assert(state.snapshot.issues[1].kind == "temperature", "NVMe hotspot warning was missed")
publish(snapshot(drive(45)))

local customThreshold = drive(55)
customThreshold.warning_temperature = 50
customThreshold.critical_temperature = 70
publish(snapshot(customThreshold))
assert(state.snapshot.issues[1].kind == "temperature" and state.snapshot.issues[1].severity == "warning",
  "per-drive temperature threshold was ignored")
publish(snapshot(drive(45)))

local partial = drive(45)
partial.smart_completeness = "partial"
publish(snapshot(partial))
assert(#state.snapshot.issues == 0, "healthy partial SMART data produced an alert")
publish(snapshot(drive(45)))

local unavailable = drive(45)
unavailable.smart_available = false
publish(snapshot(unavailable))
assert(#state.snapshot.issues == 1 and state.snapshot.issues[1].kind == "smart-unavailable",
  "unavailable SMART warning was missed")
publish(snapshot(drive(45)))

local selfTestFailure = drive(45)
selfTestFailure.self_test_state = "failed"
selfTestFailure.self_test_status = "Completed with read failure"
publish(snapshot(selfTestFailure))
assert(state.snapshot.issues[1].kind == "self-test" and state.snapshot.issues[1].severity == "critical",
  "self-test failure was missed")
publish(snapshot(drive(45)))

publish(snapshot(drive(45), "scan-100"))

local firstMissingScan = snapshot(nil, "scan-101")
publish(firstMissingScan)
assert(findIssue("drive-missing") == nil, "missing drive alerted before the grace period")
publish(firstMissingScan)
assert(findIssue("drive-missing") == nil, "reprocessing one snapshot advanced the grace period")
publish(snapshot(nil, "scan-101"))
assert(findIssue("drive-missing") == nil, "a repeated collection ID advanced the grace period")

onConfigChanged()
assert(findIssue("drive-missing") == nil, "a config refresh advanced the grace period")
dismiss({ restore_all = true, nonce = 7 })
assert(findIssue("drive-missing") == nil, "a dismissal refresh advanced the grace period")

local collectingSnapshot = snapshot(nil, "scan-collecting")
collectingSnapshot.collecting = true
publish(collectingSnapshot)
assert(findIssue("drive-missing") == nil, "an in-progress collection advanced the grace period")

local failedMissingScan = snapshot(nil, "scan-failed")
failedMissingScan.collector_error = "fixture failure"
publish(failedMissingScan)
assert(findIssue("drive-missing") == nil, "a failed collection advanced the grace period")

local blockedMissingScan = snapshot(nil, "scan-blocked")
blockedMissingScan.dependencies = {
  ready = false, blocking = true,
  missing = { "lsblk (lsblk)" }, missing_text = "lsblk (lsblk)", signature = "lsblk",
}
publish(blockedMissingScan)
assert(findIssue("drive-missing") == nil, "a blocked collection advanced the grace period")

publish(snapshot(nil, "scan-102"))
assert(findIssue("drive-missing") == nil, "missing drive alerted after only two completed scans")
publish(snapshot(nil, "scan-103"))
assert(findIssue("drive-missing") ~= nil, "three unique completed scans did not trigger a missing-drive alert")
publish(snapshot(nil, "scan-103"))
assert(findIssue("drive-missing") ~= nil, "reprocessing a snapshot removed an active missing-drive alert")

publish(snapshot(drive(45), "scan-104"))
assert(findIssue("drive-missing") == nil, "drive reappearance did not clear its missing alert")
publish(snapshot(nil, "scan-105"))
publish(snapshot(nil, "scan-106"))
assert(findIssue("drive-missing") == nil, "reappearance did not reset the missing-drive grace period")
publish(snapshot(nil, "scan-107"))
assert(findIssue("drive-missing") ~= nil, "three new scans after reappearance did not trigger an alert")

publish(snapshot(drive(45), "scan-108"))
local legacyMissingScan = snapshot(nil)
publish(legacyMissingScan)
publish(legacyMissingScan)
assert(findIssue("drive-missing") == nil, "a repeated legacy snapshot advanced the grace period")
publish(snapshot(nil))
assert(findIssue("drive-missing") == nil, "two legacy snapshot objects triggered an early alert")
publish(snapshot(nil))
assert(findIssue("drive-missing") ~= nil, "distinct legacy snapshot objects did not advance the grace period")

local missing = snapshot(nil)
missing.dependencies = {
  ready = false, blocking = true,
  missing = { "lsblk (lsblk)" }, missing_text = "lsblk (lsblk)", signature = "lsblk",
}
local notificationCountBeforeDependency = #notifications
publish(missing)
assert(findIssue("missing-dependencies") ~= nil, "dependency issue was missed")
assert(findIssue("drive-missing") ~= nil, "a blocking dependency removed an active missing-drive alert")
local dependencyCritical = false
for index = notificationCountBeforeDependency + 1, #notifications do
  if notifications[index].severity == "critical" then dependencyCritical = true end
end
assert(dependencyCritical, "blocking dependency was not critical")

local failed = snapshot(nil)
failed.collector_error = "fixture failure"
local notificationCountBeforeFailure = #notifications
publish(failed)
assert(findIssue("collector-error") ~= nil, "collector issue was missed")
assert(findIssue("drive-missing") ~= nil, "a collector failure removed an active missing-drive alert")
local collectorCritical = false
for index = notificationCountBeforeFailure + 1, #notifications do
  if notifications[index].severity == "critical" then
    collectorCritical = true
  end
end
assert(collectorCritical, "collector failure did not notify critically")
assert(#stateWrites > 0 and stateWrites[#stateWrites]:match("alert%-state%.json%.tmp$"),
  "alert state was not written to a temporary file")
assert(#stateRenames > 0 and stateRenames[#stateRenames].to:match("alert%-state%.json$"),
  "alert state was not committed atomically")

print("alert behavior tests passed")
