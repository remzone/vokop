#!/usr/bin/env ucode
// Local-only bounded process supervisor. No remote command strings are accepted.
let fs=require("fs");
let uci=require("core.uci");
let vkturn=require("subscription.vkturn");
let constants=require("core.constants");
const LIB=getenv("VOKOP_LIB")||"/usr/lib/vokop";
const RUN=getenv("VOKOP_VKTURN_STATE")||"/var/run/vokop/vkturn";
const BIN=getenv("VOKOP_VKTURN_BIN")||"/usr/bin/vokop-vk-client";
const SERVICE="vokop-vkturn";
const DISABLED=getenv("VOKOP_VKTURN_DISABLED")||"/etc/vokop/vkturn-disabled";
function q(v){return "'"+replace(""+v,/'/g,"'\\''")+"'";}
function cmd(args){let a=[];for(let v in args)push(a,q(v));return join(" ",a);}
function run(args){return system(cmd(args)+" >/dev/null 2>&1")==0;}
function read(path){try{return json(fs.readfile(path));}catch(e){return null;}}
function write(path,value){let tmp=path+".tmp";let f=fs.open(tmp,"w",0600);if(!f)return false;let ok=f.write(sprintf("%J",value)+"\n");f.close();if(ok==null){fs.unlink(tmp);return false;}return fs.rename(tmp,path);}
function plan_path(){let s=uci.get_all("vokop","settings")||{};return (s.config_path||"/etc/sing-box/config.json")+".vkturn-plan.json";}
function valid_plan(p){
    if(type(p)!="object"||p.schema!="vokop.vkturn-plan.v1"||type(p.profiles)!="array"||length(p.profiles)>32)return false;
    let ports={};let ids={};
    for(let v in p.profiles){
        if(type(v)!="object"||type(v.id)!="string"||match(v.id,/[[:cntrl:]]/)!=null||match(v.id,/^vkturn-[0-9]+$/)==null||ids[v.id]||
            type(v.port)!="int"||v.port<19000||v.port>19031||ports[v.port]||
            type(v.probe_port)!="int"||v.probe_port!=v.port+100||type(v.expires_at)!="int"||
            type(v.revision)!="int"||v.revision<1||!vkturn.turn_valid(v.turn))return false;
        ports[v.port]=true;ids[v.id]=true;
    }return true;
}
function transport_args(v){return [BIN,"-peer",v.turn.peer_host+":"+v.turn.peer_port,"-vk-link",v.turn.vk_call_url,"-listen","127.0.0.1:"+v.port,"-vless","-n",""+v.turn.streams,"-unattended=true","-status-file",RUN+"/"+v.id+".transport"];}
function service_config(p,path){
    let instances={};let now=int(clock()[0]);
    for(let v in p.profiles){if(v.expires_at<=now)continue;instances[v.id]={command:transport_args(v),respawn:[3600,5,5],term_timeout:5,stdout:false,stderr:false};}
    if(length(p.profiles)>0)instances.watchdog={command:["/usr/bin/ucode","-L",LIB,LIB+"/providers/vkturn/runtime.uc","watch",path],respawn:[3600,5,5],term_timeout:5,stdout:false,stderr:false};
    return {name:SERVICE,instances};
}
function service_present() {
    let pipe=fs.popen(cmd(["ubus","call","service","list",sprintf("%J",{name:SERVICE})])+" 2>/dev/null","r");
    if(!pipe)return true;
    let data=pipe.read("all");let code=pipe.close();
    if(code!=0)return true;
    try {let v=json(data);return type(v)!="object"||v[SERVICE]!=null;}catch(e){return true;}
}
function stop_runtime(){
    let stopped=run(["ubus","call","service","delete",sprintf("%J",{name:SERVICE})]);
    if(!stopped)stopped=!service_present();
    let status=read(RUN+"/status.json");
    if(type(status)=="object"&&type(status.profiles)=="array") {
        for(let p in status.profiles) p.state=!stopped?"stop_failed":(fs.stat(DISABLED)!=null?"disabled":"stopped");
        write(RUN+"/status.json",status);
    }
    return stopped;
}
function start_runtime(){
    let settings=uci.get_all("vokop","settings")||{};
    if(""+settings.enabled!="1")return stop_runtime();
    let path=plan_path();let p=read(path);
    if(fs.stat(DISABLED)!=null)return stop_runtime();
    if(p==null)return stop_runtime();
    if(!valid_plan(p))return false;
    if(length(p.profiles)==0)return stop_runtime();
    // The socket patch and nftables bypass MUST agree; never run unmarked.
    if(constants.NFT_OUTBOUND_MARK!="0x08000000"||!fs.stat(BIN))return false;
    if(!run(["mkdir","-p",RUN])||!run(["chmod","700",RUN]))return false;
    // Do not keep removed/expired instances when replacing a plan. The old set
    // remains untouched until validation; replacement briefly interrupts tunnels.
    if(!stop_runtime())return false;
    if(!run(["ubus","call","service","set",sprintf("%J",service_config(p,path))]))return false;
    let statuses=[];for(let v in p.profiles)push(statuses,{profile_id:v.profile_id,revision:v.revision,state:v.expires_at<=int(clock()[0])?"expired":"pending",expires_at:v.expires_at});
    return write(RUN+"/status.json",{schema:"vokop.vkturn-status.v1",profiles:statuses});
}
function probe(v){
    let pipe=fs.popen(cmd(["curl","--disable","--silent","--show-error","--fail","--max-time","5","--connect-timeout","3","--proto","=https","--proxy","socks5h://127.0.0.1:"+v.probe_port,"--output","/dev/null","--write-out","%{http_code}","https://www.gstatic.com/generate_204"])+" 2>/dev/null","r");
    if(!pipe)return false;let code=pipe.read("all");let result=pipe.close();return result==0&&code=="204";
}
function health_state(v) {
    if(probe(v))return "healthy";
    let transport=fs.readfile(RUN+"/"+v.id+".transport");
    if(transport=="captcha_required\n")return "captcha_required";
    return "degraded";
}
function watch(path){
    let p=read(path);if(!valid_plan(p))return false;
    let statuses={};let expired={};let index_value=0;
    while(true){
        let current=read(path);
        // A changed plan must restart this process through procd, not execute stale credentials.
        if(sprintf("%J",current)!=sprintf("%J",p))return true;
        if(fs.stat(DISABLED)!=null){if(stop_runtime())return true;run(["sleep","1"]);continue;}
        let now=int(clock()[0]);
        for(let v in p.profiles){
            if(v.expires_at<=now){
                if(!expired[v.id])expired[v.id]=run(["ubus","call","service","delete",sprintf("%J",{name:SERVICE,instance:v.id})]);
                statuses[v.id]={profile_id:v.profile_id,revision:v.revision,state:expired[v.id]?"expired":"expiry_stop_failed",expires_at:v.expires_at,checked_at:now};
            }
        }
        if(length(p.profiles)==0)return true;
        let v=p.profiles[index_value%length(p.profiles)];index_value++;
        if(v.expires_at>int(clock()[0])&&!expired[v.id])statuses[v.id]={profile_id:v.profile_id,revision:v.revision,state:health_state(v),expires_at:v.expires_at,checked_at:int(clock()[0])};
        let all=[];for(let entry in p.profiles)push(all,statuses[entry.id]||{profile_id:entry.profile_id,revision:entry.revision,state:"pending",expires_at:entry.expires_at});
        write(RUN+"/status.json",{schema:"vokop.vkturn-status.v1",profiles:all});
        run(["sleep","1"]);
    }
}
let mode=ARGV[0]||"";
if(mode=="start-runtime")exit(start_runtime()?0:1);
if(mode=="stop-runtime")exit(stop_runtime()?0:1);
if(mode=="watch")exit(watch(ARGV[1])?0:1);
if(mode=="validate-plan")exit(valid_plan(read(ARGV[1]))?0:1);
if(mode=="plan-service"){let p=read(ARGV[1]);if(!valid_plan(p))exit(1);print(sprintf("%J",service_config(p,ARGV[1])),"\n");exit(0);}
if(mode=="status-json"){print(sprintf("%J",read(RUN+"/status.json")||{schema:"vokop.vkturn-status.v1",profiles:[]}),"\n");exit(0);}
exit(2);
