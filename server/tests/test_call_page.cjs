const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../call_page.html'),'utf8');
const code=html.split('<script>')[1].split('</script>')[0];
let resolveMic;const sent=[],peers=[],sockets=[];
const nodes={state:{},start:{},hang:{},remote:{play:async()=>{}}};
class Peer{constructor(){this.tracks=[];this.ice=[];peers.push(this)}addTrack(t){this.tracks.push(t)}async setRemoteDescription(d){this.remoteDescription=d}async addIceCandidate(c){assert(this.remoteDescription);this.ice.push(c)}async createAnswer(){assert.equal(this.tracks.length,1);return {type:'answer'}}async createOffer(){return {type:'offer'}}async setLocalDescription(d){this.localDescription=d}close(){}}
class Socket{constructor(){this.readyState=1;sockets.push(this)}send(s){sent.push(JSON.parse(s))}close(){}}
const context={URLSearchParams,document:{getElementById:id=>nodes[id]},location:{hash:'#ticket=test',origin:'https://chat.nightwell.fun'},WebSocket:Socket,RTCPeerConnection:Peer,MediaStream:class{},navigator:{mediaDevices:{getUserMedia:()=>new Promise(r=>resolveMic=r)}},window:{addEventListener(){}},console};
vm.createContext(context);vm.runInContext(code,context);
async function receive(type,data,role){await sockets[0].onmessage({data:JSON.stringify({type,data,role})})}
(async()=>{
 await receive('connected',null,'callee');await receive('peer_ready');
 await receive('ice',{candidate:'early'});await receive('offer',{type:'offer'});
 assert.equal(peers.length,0,'must not answer before microphone permission');
 const starting=nodes.start.onclick();resolveMic({getTracks:()=>[{stop(){}}]});await starting;
 assert.equal(peers.length,1);assert.equal(peers[0].ice.length,1);assert(sent.some(m=>m.type==='answer'));
 await receive('ended');assert.equal(nodes.state.textContent,'Звонок завершён');
 console.log('PASS: early ICE queued; offer waits for microphone; answer includes audio; remote hangup closes call');
})().catch(e=>{console.error(e);process.exitCode=1});
