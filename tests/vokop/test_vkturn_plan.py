#!/usr/bin/env python3
"""Own runtime plan tests with stubbed UCI/constants; no ubus, networking, processes."""
import json, os, pathlib, subprocess, tempfile, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
UC=os.environ.get('UCODE','ucode'); LIB=ROOT/'vokop/files/usr/lib'; RUNTIME=LIB/'providers/vkturn/runtime.uc'
def plan():
    return {'schema':'vokop.vkturn-plan.v1','profiles':[{'id':'vkturn-0','profile_id':'demo','port':19000,'probe_port':19100,
      'revision':1,'expires_at':int(time.time())+600,'turn':{'peer_host':'relay.example.com','peer_port':56000,'vk_call_url':'https://vk.com/call/join/TEST','streams':2}}]}
class Plan(unittest.TestCase):
    def invoke(self,p,mode='validate-plan'):
        with tempfile.TemporaryDirectory() as td:
            d=pathlib.Path(td);(d/'core').mkdir();(d/'subscription').mkdir()
            (d/'core/uci.uc').write_text('return {get_all:function(){return {enabled:"1"};}};')
            (d/'core/constants.uc').write_text('return {NFT_OUTBOUND_MARK:"0x08000000"};')
            (d/'subscription/vkturn.uc').write_text((LIB/'subscription/vkturn.uc').read_text())
            f=d/'plan.json';f.write_text(json.dumps(p))
            return subprocess.run([UC,'-L',str(d),str(RUNTIME),mode,str(f)],capture_output=True,text=True)
    def test_valid(self):
        r=self.invoke(plan());self.assertEqual(r.returncode,0,r.stderr)
    def test_procd_arguments(self):
        r=self.invoke(plan(),'plan-service');self.assertEqual(r.returncode,0,r.stderr);v=json.loads(r.stdout)
        self.assertEqual(v['name'],'vokop-vkturn');args=v['instances']['vkturn-0']['command']
        self.assertEqual(args[0],'/usr/bin/vokop-vk-client');self.assertIn('-unattended=true',args);self.assertIn('-status-file',args)
        self.assertFalse(v['instances']['vkturn-0']['stdout']);self.assertFalse(v['instances']['vkturn-0']['stderr']);self.assertIn('watchdog',v['instances'])
    def test_expired_not_started(self):
        p=plan();p['profiles'][0]['expires_at']=int(time.time())-1
        r=self.invoke(p,'plan-service');self.assertEqual(r.returncode,0,r.stderr);self.assertNotIn('vkturn-0',json.loads(r.stdout)['instances'])
    def test_bad_port(self):
        p=plan();p['profiles'][0]['port']=22;self.assertNotEqual(self.invoke(p).returncode,0)
    def test_duplicate_port(self):
        p=plan();p['profiles'].append(dict(p['profiles'][0],id='vkturn-1'));self.assertNotEqual(self.invoke(p).returncode,0)
    def test_bad_probe(self):
        p=plan();p['profiles'][0]['probe_port']=80;self.assertNotEqual(self.invoke(p).returncode,0)
    def test_shell_injection(self):
        p=plan();p['profiles'][0]['turn']['peer_host']='example.com; touch /tmp/no';self.assertNotEqual(self.invoke(p).returncode,0)
    def test_unbounded_streams(self):
        p=plan();p['profiles'][0]['turn']['streams']=99999;self.assertNotEqual(self.invoke(p).returncode,0)
    def test_empty_native_only(self):
        p=plan();p['profiles']=[];r=self.invoke(p,'plan-service');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(r.stdout)['instances'],{})
    def test_unknown_schema(self):
        p=plan();p['schema']='other';self.assertNotEqual(self.invoke(p).returncode,0)
if __name__=='__main__':unittest.main()
