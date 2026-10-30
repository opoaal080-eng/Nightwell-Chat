import os
import tempfile
from pathlib import Path

os.environ["SECRET_KEY"] = "test-secret-key-at-least-32-characters"
os.environ["DB_PATH"] = str(Path(tempfile.mkdtemp()) / "test.sqlite")
from fastapi.testclient import TestClient
from app import app

def auth(client, name):
    r=client.post('/auth/register',json={'username':name,'password':'safe-password-123','display_name':name.title()})
    assert r.status_code == 201,r.text
    return r.json()

def headers(data): return {'Authorization':'Bearer '+data['access_token']}

def test_messaging_access_and_live_events():
    with TestClient(app) as c:
        a=auth(c,'alice');b=auth(c,'bob');outsider=auth(c,'charlie')
        ra=c.post(f"/chats/direct/{b['user']['id']}",headers=headers(a))
        assert ra.status_code == 200,ra.text
        cid=ra.json()['id']
        rb=c.post(f"/chats/direct/{a['user']['id']}",headers=headers(b))
        assert rb.json()['id']==cid
        assert c.get(f'/chats/{cid}/messages',headers=headers(outsider)).status_code==403
        with c.websocket_connect('/ws',headers=headers(b)) as ws:
            assert ws.receive_json()['type']=='connected'
            msg=c.post(f'/chats/{cid}/messages',headers=headers(a),json={'body':'Hello, Nightwell!'}).json()
            event=ws.receive_json()
            assert event['type']=='message' and event['message']['body']=='Hello, Nightwell!'
            assert len(c.get(f'/chats/{cid}/messages',headers=headers(b)).json())==1
            assert c.post(f'/chats/{cid}/read',headers=headers(b),json={'message_id':msg['id']}).status_code==200
        assert c.patch(f"/messages/{msg['id']}",headers=headers(b),json={'body':'Nope'}).status_code==403
        assert c.patch(f"/messages/{msg['id']}",headers=headers(a),json={'body':'Edited'}).json()['body']=='Edited'
        assert c.post(f"/messages/{msg['id']}/reactions",headers=headers(b),json={'emoji':'🤍'}).json()['reactions'][0]['count']==1
        assert c.delete(f"/messages/{msg['id']}",headers=headers(a)).status_code==200
        assert c.get(f'/chats/{cid}/messages',headers=headers(b)).json()[0]['deleted']==1

def test_group_access():
    with TestClient(app) as c:
        a=auth(c,'diana');b=auth(c,'edward');x=auth(c,'frank')
        r=c.post('/chats/groups',headers=headers(a),json={'title':'Friends','user_ids':[b['user']['id']]})
        cid=r.json()['id']
        assert r.status_code==201
        assert c.post(f'/chats/{cid}/messages',headers=headers(x),json={'body':'Hello'}).status_code==403
        assert c.post(f'/chats/{cid}/members',headers=headers(b),json={'user_id':x['user']['id']}).status_code==403
        assert c.post(f'/chats/{cid}/members',headers=headers(a),json={'user_id':x['user']['id']}).status_code==200
        assert c.post(f'/chats/{cid}/messages',headers=headers(x),json={'body':'Hello'}).status_code==201
