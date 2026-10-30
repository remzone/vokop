// Isolated generated tests. No daemon or system commands invoked.
let m = require('management.client');
function check(v, msg) { if (!v) die(msg + '\n'); }
let now = 1800000000;
check(m.valid_response({schema:'vokop.commands.v1',commands:[{id:1,type:'restart_vkturn',expires_at:now+60}]},now), 'valid command rejected');
check(!m.valid_response({schema:'vokop.commands.v1',commands:[{id:1,type:'restart_vkturn',expires_at:now+60,argv:['rm']}]},now), 'arbitrary arguments accepted');
check(!m.valid_response({schema:'vokop.commands.v1',commands:[{id:2,type:'restart_vkturn',expires_at:now+60},{id:1,type:'restart_vkturn',expires_at:now+60}]},now), 'unordered commands accepted');
check(!m.valid_response({schema:'vokop.commands.v1',commands:[{id:1,type:'restart_vkturn',expires_at:now+86401}]},now), 'excessive lifetime');
check(!m.command_allowed('shell') && !m.command_allowed('reboot') && !m.command_allowed('set_config'), 'unbounded command accepted');
check(m.command_allowed('refresh_subscriptions') && m.command_allowed('restart_vkturn') && m.command_allowed('disable_vkturn'), 'allowlist regression');
check(m.safe_base('https://panel.example.com/base'), 'valid HTTPS origin');
for (let u in ['http://panel.example.com','https://u:p@panel.example.com','https://panel.example.com/?secret=x','https://panel.example.com/#x','https://panel.example.com/\n']) check(!m.safe_base(u), 'unsafe origin accepted');
print('PASS management contract\n');
