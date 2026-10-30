self.addEventListener("install",event=>self.skipWaiting());
self.addEventListener("activate",event=>event.waitUntil(self.clients.claim()));
self.addEventListener("push", event=>{
  let data={};
  try{data=event.data?.json()||{};}catch(e){data={title:"Nightwell Chat",body:"Новое уведомление"};}
  const title=String(data.title||"Nightwell Chat").slice(0,100);
  const call=data.type==="incoming_call";
  const options={
    body:String(data.body||"Новое событие").slice(0,240),
    icon:"/chat-icon.svg",
    badge:"/chat-icon.svg",
    tag:call?"nw-call-"+String(data.call_id||""): "nw-chat-"+String(data.chat_id||""),
    renotify:true,
    data:{url:call?"/?call="+encodeURIComponent(String(data.call_id||"")):
         "/?chat="+encodeURIComponent(String(data.chat_id||""))},
    requireInteraction:call
  };
  event.waitUntil(self.registration.showNotification(title,options));
});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  const url=new URL(event.notification.data?.url||"/",self.registration.scope);
  event.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(async clients=>{
    for(const client of clients){
      if(new URL(client.url).origin===url.origin){
        await client.focus();return client.navigate(url.href);
      }
    }
    return self.clients.openWindow(url.href);
  }));
});
