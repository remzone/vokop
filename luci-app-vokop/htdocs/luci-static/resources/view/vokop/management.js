'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require rpc';
'require ui';

const commitManagement = rpc.declare({
    object: 'uci', method: 'commit', params: ['config'], reject: true
});

async function serviceAction(action) {
    // Only fixed local actions; no server-supplied argument or shell string.
    if (['enable', 'restart', 'stop', 'disable'].indexOf(action) < 0)
        throw new Error(_('Unsupported local service action.'));
    const result = await fs.exec('/etc/init.d/vokop-management', [action]);
    if (!result || result.code !== 0)
        throw new Error(_('Management service action failed. Check the local service status.'));
}


function validPanelURL(section, value) {
    if (!value) return true;
    if (/[\x00-\x20\x7f]/.test(value)) return _('Enter a valid HTTPS panel URL.');
    try {
        var url = new URL(value);
        return url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash
            ? true : _('Use HTTPS without credentials, query parameters or fragments.');
    } catch (e) {
        return _('Enter a valid HTTPS panel URL.');
    }
}

return view.extend({
    load: function() {
        return fs.read('/var/run/vokop/management/status.json').then(function(text) {
            try { return JSON.parse(text); } catch (e) { return null; }
        }).catch(function() { return null; });
    },
    render: function(status) {
        var map = new form.Map('vokop_management', _('Control via 3x-ui'),
            _('Optional outbound HTTPS polling. No WAN administration port is opened.'));
        var s = map.section(form.NamedSection, 'settings', 'settings', _('Local authorization'));
        s.addremove = false;
        var o = s.option(form.Flag, 'enabled', _('Allow 3x-ui control'),
            _('Enabling authorizes only refresh_subscriptions, restart_vkturn and disable_vkturn commands. The panel cannot execute arbitrary shell commands. Disable this option locally to withdraw authorization.'));
        o.default = '0';
        o.rmempty = false;
        const enabledOption = o;
        o = s.option(form.Value, 'panel_url', _('Panel HTTPS URL'));
        o.placeholder = 'https://panel.example.com';
        o.validate = validPanelURL;
        o = s.option(form.Value, 'device_id', _('Device ID'));
        o.validate = function(section, value) {
            return !value || /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(value)
                ? true : _('Use 1–64 ASCII letters, digits, dots, underscores or hyphens.');
        };
        o = s.option(form.Value, 'poll_seconds', _('Polling interval, seconds'));
        o.datatype = 'range(30,3600)';
        o.default = '60';
        o.rmempty = false;
        o = s.option(form.DummyValue, '_credential', _('Device credential'));
        o.cfgvalue = function() {
            return _('/etc/vokop/management.token — provision locally with mode 0600. The credential is never shown here.');
        };
        o = s.option(form.DummyValue, '_status', _('Management status'));
        o.cfgvalue = function() {
            if (!status || typeof status !== 'object') return _('No status available.');
            // Whitelist non-secret fields. Do not render URLs, tokens or raw payloads.
            var state = typeof status.state === 'string' ? status.state.slice(0, 100) : 'unknown';
            return state;
        };
        let actionBusy = false;
        async function localAction(action) {
            if (actionBusy) return;
            actionBusy = true;
            try {
                if (action === 'start') {
                    await map.save();
                    if (uci.get('vokop_management', 'settings', 'enabled') !== '1')
                        throw new Error(_('Select Allow 3x-ui control before starting.'));
                    await commitManagement('vokop_management');
                    await serviceAction('enable');
                    await serviceAction('restart');
                    ui.addNotification(null, E('p', _('Management configuration saved and service started.')), 'info');
                } else {
                    // Always attempt both actions, even if stopping reports an error.
                    let failed = false;
                    try { await serviceAction('stop'); } catch (e) { failed = true; }
                    try { await serviceAction('disable'); } catch (e) { failed = true; }
                    uci.set('vokop_management', 'settings', 'enabled', '0');
                    const enabledWidget = enabledOption.getUIElement('settings');
                    if (enabledWidget) enabledWidget.setValue('0');
                    await uci.save();
                    await commitManagement('vokop_management');
                    if (failed) throw new Error(_('Local authorization revoked, but a service action failed. Check the service status.'));
                    ui.addNotification(null, E('p', _('Management stopped and local authorization revoked.')), 'info');
                }
            } catch (e) {
                ui.addNotification(null, E('p', e.message || _('Management service action failed.')), 'error');
            } finally {
                actionBusy = false;
            }
        }
        o = s.option(form.Button, '_start_management', _('Apply management configuration'));
        o.inputtitle = _('Save and start management');
        o.inputstyle = 'apply';
        o.onclick = function() { return localAction('start'); };
        o = s.option(form.Button, '_stop_management', _('Withdraw local authorization'));
        o.inputtitle = _('Stop and disable management');
        o.inputstyle = 'remove';
        o.onclick = function() { return localAction('stop'); };
        return map.render();
    }
});
