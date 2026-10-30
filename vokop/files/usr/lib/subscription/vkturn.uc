// Vokop-owned versioned feed. Not an upstream VK TURN subscription standard.
let fs = require("fs");
const SCHEMA = "vokop.subscription.v1";
const MAX_BYTES = 262144;

function text(v) { return v == null ? "" : "" + v; }
function now() { return int(clock()[0]); }
function fail() { die("Invalid Vokop subscription\n"); }
function is_int(v) { return type(v) == "int" && v >= 0; }
function exact_keys(v, allowed) {
    if (type(v) != "object") return false;
    for (let k in keys(v)) if (index(allowed, k) < 0) return false;
    for (let k in allowed) if (v[k] == null) return false;
    return true;
}
function safe_id(v) { return type(v) == "string" && match(v, /[[:cntrl:]]/) == null && match(v, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/) != null; }
function valid_uuid(v) { return type(v) == "string" && match(v, /[[:cntrl:]]/) == null && match(v, /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/) != null; }
function host_valid(v) {
    if (type(v) != "string" || match(v, /[[:cntrl:][:space:]]/) != null || length(v) > 253 || index(v, ".") < 0 || match(v, /^[A-Za-z0-9.-]+$/) == null) return false;
    if (lc(v) == "localhost" || match(lc(v), /\.localhost$/) != null) return false;
    for (let p in split(v, "."))
        if (length(p) < 1 || length(p) > 63 || substr(p, 0, 1) == "-" || substr(p, length(p)-1, 1) == "-") return false;
    if (match(v, /^[0-9.]+$/)) {
        let parts = split(v, ".");
        if (length(parts) != 4) return false;
        for (let p in parts) if (int(p) > 255 || (length(p)>1 && substr(p,0,1)=="0")) return false;
        let first = int(parts[0]);
        if (first == 0 || first == 127 || first >= 224 || (first == 169 && int(parts[1]) == 254)) return false;
    }
    return true;
}
function turn_valid(v) {
    return exact_keys(v, ["peer_host", "peer_port", "vk_call_url", "streams"]) &&
        host_valid(v.peer_host) && is_int(v.peer_port) && v.peer_port >= 1 && v.peer_port <= 65535 &&
        is_int(v.streams) && v.streams >= 1 && v.streams <= 16 &&
        type(v.vk_call_url) == "string" && length(v.vk_call_url) <= 2048 && match(v.vk_call_url, /[[:cntrl:][:space:]]/) == null &&
        match(v.vk_call_url, /^https:\/\/(www\.)?vk\.com\/call\/join\/[A-Za-z0-9_=-]+$/) != null;
}
function envelope_valid(v, allow_expired) {
    if (!exact_keys(v, ["schema", "revision", "issued_at", "expires_at", "profiles"]) || v.schema != SCHEMA ||
        !is_int(v.revision) || v.revision < 1 || v.revision > 9007199254740991 ||
        !is_int(v.issued_at) || !is_int(v.expires_at) || v.issued_at > now()+300 ||
        v.expires_at <= v.issued_at || v.expires_at-v.issued_at > 2678400 || (!allow_expired && v.expires_at <= now()) ||
        type(v.profiles) != "array" || length(v.profiles)<1 || length(v.profiles)>16) return false;
    let ids = {};
    for (let p in v.profiles) {
        if (!exact_keys(p,["id","name","vless","turn"]) || !safe_id(p.id) || ids[p.id] ||
            type(p.name)!="string" || length(p.name)>100 || match(p.name, /[[:cntrl:]]/) != null ||
            !exact_keys(p.vless,["uuid"]) || !valid_uuid(p.vless.uuid) || !turn_valid(p.turn)) return false;
        ids[p.id]=true;
    }
    return true;
}

// Reject duplicate keys before json() can silently collapse them. Full nested scanner,
// escaped-key-aware, bounded depth. JSON syntax remains checked by json().
function unique_json(raw) {
    if (type(raw)!="string" || length(raw)>MAX_BYTES) return false;
    let s={i:0,n:length(raw)};
    function ws() { while(s.i<s.n && match(substr(raw,s.i,1), /[ \t\r\n]/)) s.i++; }
    function str() {
        if(substr(raw,s.i,1)!="\"") die("string");
        let begin=s.i++;
        while(s.i<s.n) { let c=substr(raw,s.i++,1); if(c=="\\") {s.i++;continue;} if(c=="\"") return json(substr(raw,begin,s.i-begin)); }
        die("string");
    }
    function val(depth) {
        if(depth>32) die("depth"); ws(); let c=substr(raw,s.i,1);
        if(c=="{") {
            s.i++;ws();let seen={};if(substr(raw,s.i,1)=="}"){s.i++;return;}
            while(true) {ws();let k=str();if(seen[k])die("duplicate");seen[k]=true;ws();if(substr(raw,s.i++,1)!=":")die("colon");val(depth+1);ws();let d=substr(raw,s.i++,1);if(d=="}")return;if(d!=",")die("comma");}
        }
        if(c=="[") {
            s.i++;ws();if(substr(raw,s.i,1)=="]"){s.i++;return;}
            while(true){val(depth+1);ws();let d=substr(raw,s.i++,1);if(d=="]")return;if(d!=",")die("comma");}
        }
        if(c=="\""){str();return;}
        let m=match(substr(raw,s.i), /^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?)/);
        if(!m)die("value");s.i+=length(m[0]);
    }
    try {val(0);ws();if(s.i!=s.n)return false;json(raw);return true;}catch(e){return false;}
}
function normalize(v) {
    if(!envelope_valid(v,false)) return null;
    let out=[];
    for(let p in v.profiles) push(out,{
        type:"vless",tag:p.id,remark:p.name,server:"127.0.0.1",server_port:19000,uuid:p.vless.uuid,
        __vokop_vkturn:{schema:SCHEMA,profile_id:p.id,revision:v.revision,issued_at:v.issued_at,expires_at:v.expires_at,turn:p.turn}
    });
    return {version:1,format:"vokop-vkturn",vokop:{schema:SCHEMA,revision:v.revision,issued_at:v.issued_at,expires_at:v.expires_at},outbounds:out};
}
function metadata_valid(m, outbound) {
    if(!exact_keys(m,["schema","profile_id","revision","issued_at","expires_at","turn"]))return false;
    return envelope_valid({schema:m.schema,revision:m.revision,issued_at:m.issued_at,expires_at:m.expires_at,
        profiles:[{id:m.profile_id,name:"",vless:{uuid:outbound.uuid},turn:m.turn}]},true) &&
        outbound.type=="vless" && outbound.server=="127.0.0.1";
}
function revision_signature(v) {
    let profiles=[];
    for(let o in v.outbounds) {
        let m=o.__vokop_vkturn;
        if(!metadata_valid(m,o)) return null;
        push(profiles,{id:m.profile_id,name:o.remark,uuid:o.uuid,revision:m.revision,issued_at:m.issued_at,expires_at:m.expires_at,
            turn:{peer_host:m.turn.peer_host,peer_port:m.turn.peer_port,vk_call_url:m.turn.vk_call_url,streams:m.turn.streams}});
    }
    return sprintf("%J",profiles);
}
function revision_allowed(candidate, previous) {
    let managed=type(candidate)=="object" && candidate.format=="vokop-vkturn";
    let old_managed=type(previous)=="object" && previous.format=="vokop-vkturn";
    if(!managed)return !old_managed;
    if(!old_managed)return true;
    if(type(candidate.vokop)!="object"||type(previous.vokop)!="object")return false;
    if(candidate.vokop.revision<previous.vokop.revision)return false;
    if(candidate.vokop.revision==previous.vokop.revision){let a=revision_signature(candidate);let b=revision_signature(previous);return a!=null&&b!=null&&a==b;}
    return true;
}
let exports={SCHEMA,MAX_BYTES,unique_json,envelope_valid,normalize,metadata_valid,revision_allowed,host_valid,turn_valid};
if(sourcepath(1)!=null&&sourcepath(1)!="")return exports;
let raw=fs.readfile(ARGV[1]);
if(ARGV[0]=="validate") {if(!unique_json(raw))exit(1);let v=json(raw);exit(envelope_valid(v,false)?0:1);}
if(ARGV[0]=="normalize") {if(!unique_json(raw))exit(1);let n=normalize(json(raw));if(n==null)exit(1);print(sprintf("%J",n),"\n");exit(0);}
exit(2);
