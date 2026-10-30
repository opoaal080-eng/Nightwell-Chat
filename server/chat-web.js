"use strict";
const $ = id=>document.getElementById(id);
let auth = localStorage.getItem("nw-chat-token") || "";
let activeChat = null;
let currentUser = null;
const status = text=>{$("status").textContent=text||"";};
async function api(path, method="GET", body=null) {
  const headers={"Accept":"application/json"};
  if(auth) headers.Authorization="Bearer "+auth;
  if(body)headers["Content-Type"]="application/json";
  const response=await fetch(path,{method,headers,body:body?JSON.stringify(body):undefined,cache:"no-store"});
  if(!response.ok) {
    const detail=await response.json().catch(()=>({}));
    throw new Error(typeof detail.detail==="string"?detail.detail:"HTTP "+response.status);
  }
  return response.json();
}
function showAuth(){ $("auth").classList.remove("hide");$("home").classList.add("hide");$("logout").classList.add("hide");}
function showHome(){ $("auth").classList.add("hide");$("home").classList.remove("hide");$("logout").classList.remove("hide");}
async function login(){
  try{
    const identity=$("identity").value.trim(), password=$("password").value;
    const phone=identity.startsWith("+")||/^[0-9]{10,}$/.test(identity);
    const result=await api(phone?"/auth/phone/login":"/auth/login","POST",
      phone?{phone:identity,password}:{username:identity,password});
    auth=result.access_token;
    localStorage.setItem("nw-chat-token",auth);
    await boot();
  }catch(e){status(e.message);}
}
async function boot(){
  if(!auth)return showAuth();
  try{currentUser=await api("/me");showHome();await refreshChats();status("");}
  catch(e){status(e.message);if(e.message.includes("401")||e.message.includes("token"))logout();}
}
function logout(){
  if(activeChat)activeChat=null;
  auth="";currentUser=null;localStorage.removeItem("nw-chat-token");
  $("conversation").classList.add("hide");showAuth();
}
async function refreshChats(){
  const chats=await api("/chats");
  const wrap=$("chats");wrap.replaceChildren();
  for(const chat of chats){
    const btn=document.createElement("button");btn.className="chatItem";
    const name=document.createElement("strong");name.textContent=chat.title||"Чат";
    const preview=document.createElement("span");preview.className="small";
    preview.textContent=" · "+(chat.last_message?.body||"");
    btn.append(name,preview);btn.addEventListener("click",()=>openChat(chat));wrap.append(btn);
  }
  if(!chats.length)wrap.textContent="Пока нет переписок";
}
async function openChat(chat){
  activeChat=chat.id;$("conversation").classList.remove("hide");
  $("chatTitle").textContent=chat.title||"Переписка";await refreshMessages();
  $("conversation").scrollIntoView({behavior:"smooth"});
}
async function refreshMessages(){
  if(activeChat===null)return;
  const data=await api("/chats/"+activeChat+"/messages");
  const wrap=$("messages");wrap.replaceChildren();
  for(const msg of data){
    const row=document.createElement("div");row.className="bubble"+(msg.sender_id===currentUser.id?" mine":"");
    const sender=document.createElement("div");sender.className="small";sender.textContent=msg.sender_name||"";
    const body=document.createElement("div");body.textContent=msg.deleted?"Сообщение удалено":msg.body||
      (msg.attachment?"📎 "+msg.attachment.filename:"");
    row.append(sender,body);wrap.append(row);
  }
  wrap.scrollTop=wrap.scrollHeight;
}
async function sendMessage(event){
  event.preventDefault();if(activeChat===null)return;
  const msg=$("message").value.trim();if(!msg)return;
  try{await api("/chats/"+activeChat+"/messages","POST",{body:msg,reply_to:null});
    $("message").value="";await refreshMessages();}catch(e){status(e.message);}
}
function base64Key(encoded){
  const padded=encoded+"=".repeat((4-encoded.length%4)%4);
  return Uint8Array.from(atob(padded.replace(/-/g,"+").replace(/_/g,"/")),x=>x.charCodeAt(0));
}
async function enablePush(){
  try{
    if(!("serviceWorker" in navigator)||!("PushManager" in window)||!("Notification" in window))
      throw new Error("Web Push не поддерживается. На iPhone установи сайт на экран «Домой».");
    const keyResult=await api("/push/vapid-public");
    if(!keyResult.public_key)throw new Error("Администратор ещё не настроил WEBPUSH_CONTACT на сервере.");
    const permission=await Notification.requestPermission();
    if(permission!=="granted")throw new Error("Разрешение на уведомления не предоставлено.");
    const registration=await navigator.serviceWorker.register("/sw.js",{scope:"/"});
    await navigator.serviceWorker.ready;
    let subscription=await registration.pushManager.getSubscription();
    if(!subscription)subscription=await registration.pushManager.subscribe({
      userVisibleOnly:true,applicationServerKey:base64Key(keyResult.public_key)});
    await api("/push/web/register","POST",subscription.toJSON());
    $("pushState").textContent="Уведомления включены для этого устройства.";
  }catch(e){$("pushState").textContent=e.message;}
}
$("login").onclick=login;$("logout").onclick=async()=>{
  try{await api("/push/web/unregister","DELETE",{});}catch(e){}
  logout();
};
$("refresh").onclick=()=>refreshChats().catch(e=>status(e.message));
$("back").onclick=()=>{$("conversation").classList.add("hide");activeChat=null;};
$("compose").onsubmit=sendMessage;
$("enablePush").onclick=enablePush;
if("serviceWorker" in navigator)navigator.serviceWorker.register("/sw.js").catch(()=>{});
boot();
document.addEventListener("visibilitychange",()=>{
  if(document.visibilityState==="visible"&&auth){
    refreshChats().catch(()=>{});
    refreshMessages().catch(()=>{});
  }
});
