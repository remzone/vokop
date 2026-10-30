#!/usr/bin/env ucode
// SPDX-License-Identifier: GPL-2.0-or-later
// Pull-only management: local opt-in, no inbound port and no arbitrary commands.
let fs = require("fs");
let uci_core = require("core.uci");
const LIB = getenv("VOKOP_LIB") || "/usr/lib/vokop";
const STATE = getenv("VOKOP_MANAGEMENT_STATE") || "/etc/vokop/management";
const RUN = getenv("VOKOP_MANAGEMENT_RUNTIME") || "/var/run/vokop/management";
const DISABLED = getenv("VOKOP_VKTURN_DISABLED") || "/etc/vokop/vkturn-disabled";
const FETCH_BIN = getenv("VOKOP_FETCH_BIN") || "/usr/bin/vokop-fetch";
const VOKOP_BIN = getenv("VOKOP_BIN") || "/usr/bin/vokop";
const UCI_BIN = getenv("VOKOP_UCI_BIN") || "/sbin/uci";
const VKTURN_INIT = getenv("VOKOP_VKTURN_INIT") || "/etc/init.d/vokop-vkturn";
function str(v) { return v == null ? "" : "" + v; }
function quote(v) { return "'" + replace(str(v), /'/g, "'\\''") + "'"; }
function command(args) { let q = []; for (let arg in args) push(q, quote(arg)); return join(" ", q); }
function run(args) { return system(command(args) + " >/dev/null 2>&1") == 0; }
function ensure(path) { return run(["mkdir", "-p", path]) && run(["chmod", "700", path]); }
function write_private(path, value) {
    let tmp = path + ".tmp";
    let f = fs.open(tmp, "w", 0600);
    if (!f) return false;
    let ok = f.write(sprintf("%J", value) + "\n") != null;
    f.close();
    if (!ok || !fs.rename(tmp, path)) { fs.unlink(tmp); return false; }
    return true;
}
function read_json(path) { try { return json(fs.readfile(path) || "null"); } catch (e) { return null; } }
function valid_id(s) { return type(s) == "string" && match(s, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/) != null; }
function safe_base(s) {
    return type(s) == "string" && length(s) <= 2048 && match(s, /[[:space:][:cntrl:]]/) == null &&
        match(s, /^https:\/\/[A-Za-z0-9.-]+(:[0-9]+)?(\/[A-Za-z0-9_.~!$&'()*+,;=:@%-]*)*\/?$/) != null;
}
function valid_response(value, now) {
    if (type(value) != "object" || value.schema != "vokop.commands.v1" || type(value.commands) != "array" || length(value.commands) > 16) return false;
    for (let key in value) if (key != "schema" && key != "commands") return false;
    let previous = 0;
    for (let c in value.commands) {
        if (type(c) != "object") return false;
        for (let key in c) if (key != "id" && key != "type" && key != "expires_at") return false;
        if (type(c.id) != "int" || c.id <= previous || c.id > 9007199254740991 || type(c.type) != "string" || length(c.type) > 64 || type(c.expires_at) != "int" || c.expires_at > now + 86400) return false;
        previous = c.id;
    }
    return true;
}
function command_allowed(kind) { return kind == "refresh_subscriptions" || kind == "restart_vkturn" || kind == "disable_vkturn"; }
function locally_authorized() {
    let p = fs.popen(command([UCI_BIN, "-q", "get", "vokop_management.settings.enabled"]) + " 2>/dev/null", "r");
    if (!p) return false;
    let value = p.read("all");
    let result = p.close();
    return result == 0 && trim(value || "") == "1";
}
function apply_command(kind) {
    if (kind == "refresh_subscriptions") return run([VOKOP_BIN, "subscription_update"]);
    if (kind == "restart_vkturn") {
        // A remote restart cannot undo an explicit kill switch.
        if (fs.stat(DISABLED)) return false;
        return run([VKTURN_INIT, "restart"]);
    }
    if (kind == "disable_vkturn") {
        if (!write_private(DISABLED, {disabled: true})) return false;
        return run([VKTURN_INIT, "stop"]);
    }
    return false;
}
function get_config() {
    let c = uci_core.get_all("vokop_management", "settings") || {};
    let seconds = int(c.poll_seconds || 60);
    return {enabled: c.enabled == "1", panel_url: str(c.panel_url), device_id: str(c.device_id), token_file: str(c.token_file || "/etc/vokop/management.token"), poll_seconds: seconds};
}
function config_valid(c) {
    return safe_base(c.panel_url) && valid_id(c.device_id) && c.token_file == "/etc/vokop/management.token" && c.poll_seconds >= 30 && c.poll_seconds <= 3600;
}
function fetch(args) { let a = [FETCH_BIN]; for (let v in args) push(a, v); return run(a); }
function status(code, last) { return write_private(RUN + "/status.json", {schema: "vokop.status.v1", state: code, last_command_id: last, at: int(clock()[0])}); }
function poll_unlocked(c) {
    if (!config_valid(c)) { status("invalid_local_config", 0); return false; }
    let enrollment = replace(c.panel_url, /\/+$/, "") + "/" + c.device_id;
    let state = read_json(STATE + "/state.json");
    // Cursor and pending ACKs belong to one enrollment, not to the physical router.
    // A local origin/device change starts a new queue and never transmits old results.
    if (type(state) != "object" || state.enrollment != enrollment) {
        state = {enrollment: enrollment, last: 0, results: []};
        if (!write_private(STATE + "/state.json", state)) return false;
    }
    let last = type(state.last) == "int" && state.last >= 0 ? state.last : 0;
    state.last = last;
    if (type(state.results) != "array") state.results = [];
    let base = replace(c.panel_url, /\/+$/, "") + "/api/vokop/v1/devices/" + c.device_id;
    // Replay the exact saved acknowledgement before asking for more commands.
    if (type(state.results) == "array" && length(state.results) > 0) {
        write_private(RUN + "/ack.json", {schema: "vokop.ack.v1", results: state.results});
        if (!fetch(["--url", base + "/ack", "--method", "POST", "--token-file", c.token_file, "--body-file", RUN + "/ack.json", "--output", RUN + "/ack-response.json"])) { status("ack_pending", last); return false; }
        state.results = [];
        if (!write_private(STATE + "/state.json", state)) return false;
    }
    if (!fetch(["--url", base + "/commands?after=" + last, "--token-file", c.token_file, "--output", RUN + "/commands.json"])) { status("panel_unavailable", last); return false; }
    let info = fs.stat(RUN + "/commands.json");
    if (!info || info.size > 65536) { status("invalid_response", last); return false; }
    let raw = fs.readfile(RUN + "/commands.json");
    if (!require("subscription.vkturn").unique_json(raw)) { status("invalid_response", last); return false; }
    let value = read_json(RUN + "/commands.json");
    let now = int(clock()[0]);
    if (!valid_response(value, now)) { status("invalid_response", last); return false; }
    for (let c in value.commands) {
        if (c.id <= state.last) continue;
        if (!locally_authorized()) { status("authorization_withdrawn", state.last); return false; }
        let outcome = c.expires_at <= int(clock()[0]) ? "expired" : (!command_allowed(c.type) ? "rejected" : (apply_command(c.type) ? "applied" : "failed"));
        state.last = c.id;
        push(state.results, {id: c.id, status: outcome});
        // Allowed commands are idempotent if power loss occurs before this save.
        if (!write_private(STATE + "/state.json", state)) { status("state_write_failed", last); return false; }
    }
    status("ready", state.last);
    return true;
}
function poll_once(c) {
    let lock = RUN + "/poll.lock";
    if (!fs.mkdir(lock, 0700)) {
        let owner = trim(fs.readfile(lock + "/owner") || "");
        let info = fs.stat(lock);
        let numeric = match(owner, /^[0-9]{1,10}$/) != null;
        if (numeric && run(["kill", "-0", owner])) return false;
        if (!numeric && info && int(info.mtime) + 60 >= int(clock()[0])) return false;
        fs.unlink(lock + "/owner");
        fs.rmdir(lock);
        if (!fs.mkdir(lock, 0700)) return false;
    }
    let owner = fs.readlink("/proc/self");
    if (!owner || fs.writefile(lock + "/owner", owner) == null) { fs.rmdir(lock); return false; }
    let result = false;
    try { result = poll_unlocked(c); }
    catch (e) { status("internal_error", 0); }
    fs.unlink(lock + "/owner");
    fs.rmdir(lock);
    return result;
}
function main() {
    if (!ensure(STATE) || !ensure(RUN)) return 1;
    while (true) {
        let c = get_config();
        if (!c.enabled) { status("disabled", 0); return 0; }
        poll_once(c);
        if (ARGV[0] == "once") return 0;
        run(["sleep", config_valid(c) ? c.poll_seconds : 60]);
    }
}
if (sourcepath(1) != null && sourcepath(1) != "") return {valid_response, command_allowed, safe_base, config_valid, poll_once, ensure};
if (ARGV[0] != "run" && ARGV[0] != "once") exit(2);
exit(main());
