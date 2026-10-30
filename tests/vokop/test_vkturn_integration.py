#!/usr/bin/env python3
"""Native parser/generator integration on temporary fixtures. No service or network."""
import copy,json,os,pathlib,subprocess,tempfile,time,unittest
from test_vkturn_contract import fixture,UC,LIB
PARSER=LIB/'subscription/parser.uc';GENERATOR=LIB/'singbox/generator.uc'
class Integration(unittest.TestCase):
    def run_module(self,module,*args,env=None):
        return subprocess.run([UC,'-L',str(LIB),str(module),*map(str,args)],env=env,capture_output=True,text=True)
    def generate(self,feed,sections=1,mutate=None):
        with tempfile.TemporaryDirectory() as td:
            d=pathlib.Path(td);cache=d/'subs';cache.mkdir();raw=d/'raw.json';raw.write_text(json.dumps(feed));normalized=d/'normalized.json'
            parsed=self.run_module(PARSER,'normalize-content-validated',raw,normalized)
            self.assertEqual(parsed.returncode,0,parsed.stderr)
            value=json.loads(normalized.read_text())
            if mutate:mutate(value)
            rules=[]
            for i in range(sections):
                name='proxy'+str(i);prefix=cache/(name+'-subscription-1')
                pathlib.Path(str(prefix)+'.json').write_text(json.dumps(value));pathlib.Path(str(prefix)+'.url').write_text('https://example.com/sub.json')
                pathlib.Path(str(prefix)+'.user_agent').write_text('Happ')
                rules.append({'.name':name,'.type':'section','enabled':'1','action':'connection','subscription_urls':['https://example.com/sub.json'],'domain_suffix':['test'+str(i)+'.example']})
            config={'settings':{'.name':'settings','.type':'settings','config_path':'/tmp/vokop-test-unused.json','dns_server':'1.1.1.1','service_listen_address':'127.0.0.1'},'section':rules}
            f=d/'fixture.json';f.write_text(json.dumps(config));output=d/'config.json';pathlib.Path(str(output)+'.section-cache').mkdir()
            env=dict(os.environ,TMP_SUBSCRIPTION_FOLDER=str(cache))
            result=self.run_module(GENERATOR,'generate-config-fixture',f,output,'127.0.0.1','0',env=env)
            self.assertEqual(result.returncode,0,result.stderr)
            plan_path=pathlib.Path(str(output)+'.vkturn-plan.json')
            self.assertEqual(plan_path.stat().st_mode & 0o777,0o600)
            return json.loads(output.read_text()),json.loads(plan_path.read_text())
    def test_real_parser_generator(self):
        config,plan=self.generate(fixture())
        self.assertEqual(len(plan['profiles']),1)
        out=[o for o in config['outbounds'] if o.get('type')=='vless'];self.assertEqual(len(out),1)
        self.assertEqual((out[0]['server'],out[0]['server_port']),('127.0.0.1',19000))
        self.assertNotIn('__vokop_vkturn',json.dumps(config));self.assertNotIn('vk_call_url',json.dumps(config))
        self.assertTrue(any(i.get('listen_port')==19100 and i.get('listen')=='127.0.0.1' for i in config['inbounds']))
        self.assertTrue(any(r.get('outbound')==out[0]['tag'] and r.get('inbound')==['vkturn-probe-0'] for r in config['route']['rules']))
    def test_multiple_sources_no_port_collision(self):
        feed=fixture();feed['profiles'].append(dict(copy.deepcopy(feed['profiles'][0]),id='second'))
        config,plan=self.generate(feed,sections=2)
        self.assertEqual(sorted(p['port'] for p in plan['profiles']),[19000,19001,19002,19003])
        self.assertEqual(len(set(o['tag'] for o in config['outbounds'])),len(config['outbounds']))
    def test_expired_cache_keeps_closed_outbound(self):
        def expire(v):
            for o in v['outbounds']:o['__vokop_vkturn']['expires_at']=int(time.time())-1
        config,plan=self.generate(fixture(),mutate=expire)
        self.assertTrue(any(o.get('server')=='127.0.0.1' and o.get('type')=='vless' for o in config['outbounds']))
        self.assertLess(plan['profiles'][0]['expires_at'],time.time())
    def test_untrusted_internal_metadata_stripped(self):
        with tempfile.TemporaryDirectory() as td:
            d=pathlib.Path(td);raw=d/'raw';out=d/'out'
            raw.write_text(json.dumps({'outbounds':[{'type':'vless','server':'example.com','server_port':443,'uuid':fixture()['profiles'][0]['vless']['uuid'],'__vokop_vkturn':{'command':'malicious'}}]}))
            result=self.run_module(PARSER,'normalize-content-validated',raw,out)
            self.assertEqual(result.returncode,0,result.stderr);self.assertNotIn('__vokop_vkturn',out.read_text())
if __name__=='__main__':unittest.main()
