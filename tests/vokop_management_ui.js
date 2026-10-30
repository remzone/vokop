#!/usr/bin/env node
// Isolated UI contract test. Does not execute the agent, init scripts, or router commands.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'luci-app-vokop/htdocs/luci-static/resources/view/vokop/management.js'), 'utf8');
const options = {};
let configName;
let enabled = "0";
let calls = [];
let notifications = [];
let failStop = false;
class MapStub {
    constructor(name) { configName = name; }
    section(type, name, kind) {
        assert.equal(name, 'settings');
        assert.equal(kind, 'settings');
        return { option(type, key) { return options[key] = { getUIElement: () => ({ setValue: value => { assert.equal(value, "0"); } }) }; } };
    }
    save() { calls.push("save"); return Promise.resolve(); }
    render() { return options; }
}
const app = vm.runInNewContext('(function(){' + source + '\n})()', {
    URL,
    _: value => value,
    view: { extend: value => value },
    form: { Map: MapStub },
    E: (tag, text) => text,
    ui: { addNotification: (unused, message, type) => notifications.push({ message, type }) },
    uci: {
        get: () => enabled,
        set: (config, section, key, value) => {
            assert.equal(config, 'vokop_management');
            assert.equal(section, 'settings');
            assert.equal(key, 'enabled');
            enabled = value;
            calls.push('set:' + value);
        },
        save: () => { calls.push('uci-save'); return Promise.resolve(); }
    },
    rpc: { declare: spec => {
        assert.equal(spec.object, 'uci');
        assert.equal(spec.method, 'commit');
        return config => { assert.equal(config, 'vokop_management'); calls.push('commit'); return Promise.resolve(); };
    } },
    fs: {
        read: () => Promise.reject(new Error('No daemon in unit test')),
        exec: (file, args) => {
            assert.equal(file, '/etc/init.d/vokop-management');
            assert.equal(args.length, 1);
            assert.ok(['enable', 'restart', 'stop', 'disable'].includes(args[0]));
            calls.push(args[0]);
            return Promise.resolve({ code: failStop && args[0] === 'stop' ? 1 : 0 });
        }
    }
});
app.render({ state: 'ready', token: 'MUST_NOT_LEAK', url: 'https://secret.invalid' });
assert.equal(configName, 'vokop_management');
assert.equal(options.enabled.default, '0');
assert.equal(options.poll_seconds.datatype, 'range(30,3600)');
for (const good of ['', 'https://panel.example.com', 'https://panel.example.com/base/path', 'https://panel.example.com:8443'])
    assert.equal(options.panel_url.validate('', good), true, good);
for (const bad of ['http://panel.example.com', 'javascript:alert(1)', 'https://u:p@panel.example.com', 'https://panel.example.com?token=secret', 'https://panel.example.com#fragment', 'not a URL', ' https://panel.example.com', 'https://panel.example.com/with space'])
    assert.notEqual(options.panel_url.validate('', bad), true, bad);
for (const good of ['', 'router_01', 'ROUTER-123', 'router.example'])
    assert.equal(options.device_id.validate('', good), true, good);
for (const bad of ['a; reboot', '../token', 'x'.repeat(65), 'роутер', 'with space'])
    assert.notEqual(options.device_id.validate('', bad), true, bad);
assert.equal(options._status.cfgvalue(), 'ready');
assert.equal(Object.hasOwn(options, 'token_file'), false);
assert.equal(Object.hasOwn(options, 'token'), false);
const acl = JSON.parse(fs.readFileSync(path.join(root, 'luci-app-vokop/root/usr/share/rpcd/acl.d/luci-app-vokop-management.json'), 'utf8'))['luci-app-vokop-management'];
assert.deepEqual(Object.keys(acl.read.file), ['/var/run/vokop/management/status.json']);
assert.equal(JSON.stringify(acl).includes('management.token'), false);
assert.deepEqual(Object.keys(acl.write.file), ['/etc/init.d/vokop-management']);
assert.deepEqual(acl.write.file['/etc/init.d/vokop-management'], ['exec']);
assert.deepEqual(calls, [], 'render must not auto-start management');
(async function() {
    await options._start_management.onclick();
    assert.deepEqual(calls, ['save'], 'disabled flag must prevent service actions');
    assert.equal(notifications.at(-1).type, 'error');
    calls = [];
    enabled = '1';
    await Promise.all([options._start_management.onclick(), options._start_management.onclick()]);
    assert.deepEqual(calls, ['save', 'commit', 'enable', 'restart'], 'concurrent clicks must not duplicate operations');
    assert.equal(notifications.at(-1).type, 'info');
    calls = [];
    await options._stop_management.onclick();
    assert.deepEqual(calls, ['stop', 'disable', 'set:0', 'uci-save', 'commit']);
    assert.equal(enabled, '0');
    assert.equal(notifications.at(-1).type, 'info');
    calls = [];
    enabled = '1';
    failStop = true;
    await options._stop_management.onclick();
    assert.deepEqual(calls, ['stop', 'disable', 'set:0', 'uci-save', 'commit']);
    assert.equal(enabled, '0', 'stop failure must still revoke saved authorization');
    assert.equal(notifications.at(-1).type, 'error');
    console.log('PASS: management UI validation, local activation/revocation, duplicate clicks and secret-safe ACL');
})().catch(error => { console.error(error); process.exitCode = 1; });
