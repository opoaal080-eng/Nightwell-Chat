from fastapi.testclient import TestClient
from app import app, setup
from test_api import auth, headers


def test_stickers_survive_reload_and_keep_legacy_text_fallback():
    with TestClient(app) as c:
        a=auth(c,'stickerone');b=auth(c,'stickertwo');o=auth(c,'stickerout')
        ah,bh,oh=map(headers,(a,b,o))
        cid=c.post(f"/chats/direct/{b['user']['id']}",headers=ah).json()['id']
        url=f'/chats/{cid}/messages'
        plain=c.post(url,headers=ah,json={'body':'old client'}).json()
        assert plain['visual']=='text'
        sent=c.post(url,headers=ah,json={'body':'🔥','visual':'sticker','reply_to':plain['id']})
        assert sent.status_code==201
        msg=sent.json()
        assert msg['body']=='🔥' and msg['visual']=='sticker' and msg['reply_to']==plain['id']
        setup()  # Additive migration remains safe on an existing database.
        loaded=c.get(url,headers=bh).json()
        assert loaded[-1]['visual']=='sticker' and loaded[0]['body']=='old client'
        assert c.post(url,headers=oh,json={'body':'🔥','visual':'sticker'}).status_code==403
        assert c.post(url,headers=ah,json={'body':'fake','visual':'sticker'}).status_code==422
        assert c.post(url,headers=ah,json={'body':'🔥','visual':'arbitrary'}).status_code==422
        changed=c.patch(f"/messages/{msg['id']}",headers=ah,json={'body':'Edited from an older client'}).json()
        assert changed['visual']=='text'
        assert c.delete(f"/messages/{msg['id']}",headers=ah).status_code==200
        assert c.get(url,headers=bh).json()[-1]['deleted']==1
