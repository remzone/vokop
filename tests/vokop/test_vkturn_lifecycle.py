#!/usr/bin/env python3
"""Provider service tests against a generated ubus stub; never touches real network."""
import json, os, pathlib, subprocess, tempfile, time, unittest
from test_vkturn_plan import plan, ROOT, UC, LIB, RUNTIME
class Lifecycle(unittest.TestCase):
    def invoke(self,enabled='1',disabled=False,mark='0x08000000',ubus_failure=False):
        with tempfile.TemporaryDirectory() as td:
            d=pathlib.Path(td);(d/'core').mkdir();(d/'subscription').mkdir();(d/'bin').mkdir()
            config=d/'config.json';feed=d/'config.json.vkturn-plan.json';feed.write_text(json.dumps(plan()))
            (d/'core/uci.uc').write_text('return {get_all:function(){return '+json.dumps({'enabled':enabled,'config_path':str(config)})+';}};')
            (d/'core/constants.uc').write_text('return '+json.dumps({'NFT_OUTBOUND_MARK':mark})+';')
            (d/'subscription/vkturn.uc').write_text((LIB/'subscription/vkturn.uc').read_text())
            stub=d/'bin/ubus';stub.write_text('#!/usr/bin/env python3\nimport os,sys,json\nwith open(os.environ["STUB_LOG"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nif os.environ.get("STUB_FAIL")=="1":sys.exit(1)\nprint("{}")\n');stub.chmod(0o755)
            lock=d/'disabled';log=d/'ubus.log'
            if disabled:lock.write_text('{}')
            env=dict(os.environ,PATH=str(d/'bin')+':'+os.environ['PATH'],VOKOP_VKTURN_BIN='/bin/true',VOKOP_VKTURN_DISABLED=str(lock),VOKOP_VKTURN_STATE=str(d/'state'),VOKOP_LIB=str(d),STUB_LOG=str(log),STUB_FAIL='1' if ubus_failure else '0')
            r=subprocess.run([UC,'-L',str(d),str(RUNTIME),'start-runtime'],env=env,capture_output=True,text=True)
            commands=[json.loads(x) for x in log.read_text().splitlines()] if log.exists() else []
            status=json.loads((d/'state/status.json').read_text()) if (d/'state/status.json').exists() else None
            return r,commands,status
    def watch_once(self, expired=False, probe_ok=False, captcha=False):
        with tempfile.TemporaryDirectory() as td:
            d=pathlib.Path(td);(d/'core').mkdir();(d/'subscription').mkdir();(d/'bin').mkdir();(d/'state').mkdir()
            p=plan()
            if expired:p['profiles'][0]['expires_at']=int(time.time())-1
            feed=d/'plan.json';feed.write_text(json.dumps(p))
            (d/'core/uci.uc').write_text('return {};')
            (d/'core/constants.uc').write_text('return {};')
            (d/'subscription/vkturn.uc').write_text((LIB/'subscription/vkturn.uc').read_text())
            for name,content in [('ubus','#!/bin/sh\nexit 0\n'),('curl','#!/bin/sh\nprintf '+('204' if probe_ok else '500')+'\nexit '+('0' if probe_ok else '1')+'\n')]:
                f=d/'bin'/name;f.write_text(content);f.chmod(0o755)
            if captcha:(d/'state/vkturn-0.transport').write_text('captcha_required\n')
            env=dict(os.environ,PATH=str(d/'bin')+':'+os.environ['PATH'],VOKOP_VKTURN_DISABLED=str(d/'disabled'),VOKOP_VKTURN_STATE=str(d/'state'))
            proc=subprocess.Popen([UC,'-L',str(d),str(RUNTIME),'watch',str(feed)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
            try:
                until=time.monotonic()+3
                while not (d/'state/status.json').exists() and time.monotonic()<until and proc.poll() is None:time.sleep(.02)
                self.assertTrue((d/'state/status.json').exists())
                status=json.loads((d/'state/status.json').read_text())
            finally:
                proc.terminate();proc.communicate(timeout=2)
            return status
    def test_watch_expiry(self):self.assertEqual(self.watch_once(expired=True)['profiles'][0]['state'],'expired')
    def test_watch_health_requires_probe(self):self.assertEqual(self.watch_once(probe_ok=True)['profiles'][0]['state'],'healthy')
    def test_watch_bad_probe(self):self.assertEqual(self.watch_once()['profiles'][0]['state'],'degraded')
    def test_watch_captcha(self):self.assertEqual(self.watch_once(captcha=True)['profiles'][0]['state'],'captcha_required')
    def test_start_pending_not_healthy(self):
        r,c,s=self.invoke();self.assertEqual(r.returncode,0,r.stderr);self.assertTrue(any(x[2]=='set' for x in c));self.assertEqual(s['profiles'][0]['state'],'pending')
        self.assertNotIn('vk_call_url',json.dumps(s));self.assertNotIn('TEST',json.dumps(s))
    def test_local_disabled(self):
        r,c,s=self.invoke(enabled='0');self.assertEqual(r.returncode,0,r.stderr);self.assertFalse(any(x[2]=='set' for x in c))
    def test_sticky_disabled(self):
        r,c,s=self.invoke(disabled=True);self.assertEqual(r.returncode,0,r.stderr);self.assertFalse(any(x[2]=='set' for x in c))
    def test_mark_mismatch_fails_closed(self):
        r,c,s=self.invoke(mark='0x00200000');self.assertNotEqual(r.returncode,0);self.assertFalse(any(x[2]=='set' for x in c))
    def test_procd_failure(self):
        r,c,s=self.invoke(ubus_failure=True);self.assertNotEqual(r.returncode,0);self.assertIsNone(s)
if __name__=='__main__':unittest.main()
