#!/usr/bin/env python3
"""Isolated tests: generated fixtures only; no network or router state changes."""
import copy, json, os, pathlib, subprocess, tempfile, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
UC=os.environ.get('UCODE','ucode')
LIB=ROOT/'vokop/files/usr/lib'
MODULE=LIB/'subscription/vkturn.uc'

def fixture():
    now=int(time.time())
    return {'schema':'vokop.subscription.v1','revision':1,'issued_at':now-10,'expires_at':now+600,
       'profiles':[{'id':'test-1','name':'Тест','vless':{'uuid':'11111111-2222-4333-8444-555555555555'},
       'turn':{'peer_host':'relay.example.com','peer_port':56000,'vk_call_url':'https://vk.com/call/join/TEST_TOKEN','streams':2}}]}

class Contract(unittest.TestCase):
    def invoke(self,value,mode='validate',raw=False):
        with tempfile.TemporaryDirectory() as td:
            p=pathlib.Path(td)/'feed.json';p.write_text(value if raw else json.dumps(value))
            return subprocess.run([UC,'-L',str(LIB),str(MODULE),mode,str(p)],capture_output=True,text=True)
    def valid(self,v):
        r=self.invoke(v);self.assertEqual(r.returncode,0,r.stderr)
    def invalid(self,v,raw=False):
        r=self.invoke(v,raw=raw);self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
    def test_valid(self):self.valid(fixture())
    def test_normalize(self):
        r=self.invoke(fixture(),'normalize');self.assertEqual(r.returncode,0,r.stderr)
        v=json.loads(r.stdout);self.assertEqual(v['format'],'vokop-vkturn');self.assertEqual(v['outbounds'][0]['server'],'127.0.0.1')
        self.assertEqual(v['outbounds'][0]['__vokop_vkturn']['profile_id'],'test-1')
    def revision(self, mode):
        # Invoke only the new contract module; no native services or upstream scripts.
        with tempfile.TemporaryDirectory() as td:
            script=pathlib.Path(td)/'revision.uc'
            script.write_text('let m=require("subscription.vkturn"); let v=json(ARGV[0]); let a=m.normalize(v); let b=m.normalize(v); '
                + 'if(ARGV[1]=="lower") b.vokop.revision=0; '
                + 'if(ARGV[1]=="changed") b.outbounds[0].uuid="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"; '
                + 'if(ARGV[1]=="sharelink") a.outbounds[0].share_link="generated"; '
                + 'if(ARGV[1]=="higher") {b.vokop.revision=2;b.outbounds[0].__vokop_vkturn.revision=2;} '
                + 'if(ARGV[1]=="downgrade") b={outbounds:[]}; '
                + 'if(ARGV[1]=="generic") {a={outbounds:[]};b={outbounds:[]};} '
                + 'exit(m.revision_allowed(b,a)?0:1);')
            return subprocess.run([UC,'-L',str(LIB),str(script),json.dumps(fixture()),mode],capture_output=True,text=True)
    def test_revision_identical(self):self.assertEqual(self.revision('same').returncode,0)
    def test_revision_lower(self):self.assertNotEqual(self.revision('lower').returncode,0)
    def test_revision_changed_same(self):self.assertNotEqual(self.revision('changed').returncode,0)
    def test_revision_sharelink_ignored(self):self.assertEqual(self.revision('sharelink').returncode,0)
    def test_revision_higher(self):self.assertEqual(self.revision('higher').returncode,0)
    def test_revision_downgrade(self):self.assertNotEqual(self.revision('downgrade').returncode,0)
    def test_revision_generic(self):self.assertEqual(self.revision('generic').returncode,0)
    def test_duplicate_top_key(self):self.invalid(json.dumps(fixture()).replace('"revision": 1','"revision": 1, "revision": 2'),True)
    def test_duplicate_escaped_key(self):self.invalid(json.dumps(fixture()).replace('"revision": 1','"revision": 1, "revis\\u0069on": 2'),True)
    def test_duplicate_nested_key(self):self.invalid(json.dumps(fixture()).replace('"streams": 2','"streams": 2, "streams": 3'),True)
    def test_unknown(self):
        v=fixture();v['command']='rm -rf /';self.invalid(v)
    def test_expired(self):
        v=fixture();v['expires_at']=int(time.time())-1;self.invalid(v)
    def test_future(self):
        v=fixture();v['issued_at']=int(time.time())+600;self.invalid(v)
    def test_lifetime(self):
        v=fixture();v['expires_at']=v['issued_at']+2678401;self.invalid(v)
    def test_duplicate_id(self):
        v=fixture();v['profiles']*=2;self.invalid(v)
    def test_many(self):
        v=fixture();v['profiles']=[dict(v['profiles'][0],id='test-'+str(i)) for i in range(17)];self.invalid(v)
    def test_integer_only(self):
        v=fixture();v['revision']=1.5;self.invalid(v)
    def test_bool_not_number(self):
        v=fixture();v['revision']=True;self.invalid(v)
    def test_uuid(self):
        v=fixture();v['profiles'][0]['vless']['uuid']='$(id)';self.invalid(v)
    def test_shell_peer(self):
        v=fixture();v['profiles'][0]['turn']['peer_host']='relay.example.com;id';self.invalid(v)
    def test_peer_loopback(self):
        v=fixture();v['profiles'][0]['turn']['peer_host']='127.0.0.1';self.invalid(v)
    def test_port(self):
        v=fixture();v['profiles'][0]['turn']['peer_port']=65536;self.invalid(v)
    def test_http(self):
        v=fixture();v['profiles'][0]['turn']['vk_call_url']='http://vk.com/call/join/TEST';self.invalid(v)
    def test_wrong_path(self):
        v=fixture();v['profiles'][0]['turn']['vk_call_url']='https://vk.com/call/TEST';self.invalid(v)
    def test_wrong_origin(self):
        v=fixture();v['profiles'][0]['turn']['vk_call_url']='https://vk.com.evil.test/call/join/TEST';self.invalid(v)
    def test_url_newline(self):
        v=fixture();v['profiles'][0]['turn']['vk_call_url']+='\n';self.invalid(v)
    def test_id_newline(self):
        v=fixture();v['profiles'][0]['id']+='\n';self.invalid(v)
    def test_name_control(self):
        v=fixture();v['profiles'][0]['name']='x\nx';self.invalid(v)
    def test_trailing_data(self):self.invalid(json.dumps(fixture())+' {}',True)
    def test_too_large(self):self.invalid(' '*262145,True)

if __name__=='__main__': unittest.main()
