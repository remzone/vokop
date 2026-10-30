#!/usr/bin/env python3
"""Generated isolated persistence tests. Fake panel and service executables, no network."""
import json, os, pathlib, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
UCODE = os.environ.get('UCODE', 'ucode')
with tempfile.TemporaryDirectory(prefix='vokop-queue-') as td:
    t = pathlib.Path(td)
    for name in ['state', 'run']:
        (t/name).mkdir()
    fetch = t/'fetch'
    fetch.write_text('''#!/usr/bin/env python3
import sys,os,json,pathlib
args=sys.argv[1:]; get=lambda k:args[args.index(k)+1]
t=pathlib.Path(os.environ['TEST_DIR']); url=get('--url')
if url.endswith('/ack') and (t/'fail-ack').exists(): sys.exit(1)
if '/commands?' in url:
    value=json.loads((t/'commands').read_text())
else:
    value={}; (t/'ack').write_text(pathlib.Path(get('--body-file')).read_text())
pathlib.Path(get('--output')).write_text(json.dumps(value))
''')
    fetch.chmod(0o755)
    auth=t/'auth';auth.write_text('#!/bin/sh\nprintf \"1\\n\"\n');auth.chmod(0o755)
    action = t/'action'
    action.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_DIR/actions"\n')
    action.chmod(0o755)
    (t/'commands').write_text(json.dumps({'schema':'vokop.commands.v1','commands':[{'id':1,'type':'refresh_subscriptions','expires_at':int(time.time())+300}]}))
    script = t/'test.uc'
    script.write_text('''let m=require("management.client"); m.poll_once({panel_url:"https://panel.example", device_id:"test", token_file:"/etc/vokop/management.token", poll_seconds:60});''')
    env = dict(os.environ, TEST_DIR=td, VOKOP_MANAGEMENT_STATE=str(t/'state'), VOKOP_MANAGEMENT_RUNTIME=str(t/'run'), VOKOP_FETCH_BIN=str(fetch), VOKOP_UCI_BIN=str(auth), VOKOP_BIN=str(action), VOKOP_VKTURN_INIT=str(action), VOKOP_VKTURN_DISABLED=str(t/'disabled'))
    def poll(): subprocess.run([UCODE,'-L',str(ROOT/'vokop/files/usr/lib'),str(script)],env=env,check=True)
    poll()
    assert json.loads((t/'state/state.json').read_text())['last'] == 1
    (t/'fail-ack').touch(); poll()
    assert (t/'actions').read_text().splitlines() == ['subscription_update']
    assert json.loads((t/'run/status.json').read_text())['state'] == 'ack_pending'
    (t/'fail-ack').unlink(); poll()
    assert (t/'actions').read_text().splitlines() == ['subscription_update'], 'replayed executed command after ACK retry'
    assert json.loads((t/'ack').read_text())['results'] == [{'id':1,'status':'applied'}]
    # Re-enrollment cannot send an old pending ACK or retain an old cursor.
    state=json.loads((t/'state/state.json').read_text());state['results']=[{'id':999,'status':'applied'}];state['last']=999
    (t/'state/state.json').write_text(json.dumps(state)); (t/'ack').unlink()
    script.write_text(script.read_text().replace('device_id:"test"','device_id:"new-device"'))
    poll()
    assert not (t/'ack').exists(), 'old ACK leaked to new device'
    assert json.loads((t/'state/state.json').read_text())['last'] == 1
    assert len((t/'actions').read_text().splitlines()) == 2, 'new device cursor not reset'
    # Every command gets a fresh expiry check after a slow previous command.
    script.write_text(script.read_text().replace('device_id:"new-device"','device_id:"expiry-test"'))
    (t/'commands').write_text(json.dumps({'schema':'vokop.commands.v1','commands':[{'id':1,'type':'refresh_subscriptions','expires_at':int(time.time())+60},{'id':2,'type':'restart_vkturn','expires_at':int(time.time())+1}]}))
    action.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_DIR/actions"\nsleep 2\n')
    poll()
    results=json.loads((t/'state/state.json').read_text())['results']
    assert results == [{'id':1,'status':'applied'},{'id':2,'status':'expired'}], results
    for p in (t/'state').iterdir(): assert p.stat().st_mode & 0o777 == 0o600
print('PASS management durable acknowledgement and replay safety')
