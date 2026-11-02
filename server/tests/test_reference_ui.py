from fastapi.testclient import TestClient
from app import app, db
from test_api import auth,headers

def test_group_profile_and_leaving_transfers_ownership():
    with TestClient(app) as c:
        a=auth(c,'refowner');b=auth(c,'refmember');o=auth(c,'refoutsider')
        ah,bh,oh=map(headers,(a,b,o))
        cid=c.post('/chats/groups',headers=ah,json={'title':'Design','user_ids':[b['user']['id']]}).json()['id']
        detail=c.get(f'/chats/{cid}/details',headers=ah).json()
        assert len(detail['members'])==2 and detail['role']=='owner'
        assert c.get(f'/chats/{cid}/details',headers=oh).status_code==403
        assert c.patch(f'/chats/{cid}/notifications',headers=oh,json={'muted':True}).status_code==403
        assert c.patch(f'/chats/{cid}/notifications',headers=ah,json={'muted':True}).status_code==200
        assert c.get(f'/chats/{cid}/details',headers=ah).json()['muted'] is True
        assert c.get(f'/chats/{cid}/details',headers=bh).json()['muted'] is False
        assert c.delete(f'/chats/{cid}/membership',headers=ah).status_code==200
        assert c.get(f'/chats/{cid}/details',headers=ah).status_code==403
        assert c.get(f'/chats/{cid}/details',headers=bh).json()['role']=='owner'

def test_history_is_private_and_expired_unanswered_is_missed():
    with TestClient(app) as c:
        a=auth(c,'refcaller');b=auth(c,'refcallee');o=auth(c,'refcalloutsider')
        ah,bh,oh=map(headers,(a,b,o))
        cid=c.post(f"/chats/direct/{b['user']['id']}",headers=ah).json()['id']
        call=c.post(f"/calls/direct/{b['user']['id']}",headers=ah).json()['id']
        with db() as con: con.execute('UPDATE calls SET expires_at=0 WHERE id=?',(call,))
        c.get('/calls/pending',headers=bh)
        assert c.get('/calls/history',headers=bh).json()[0]['missed'] is True
        assert c.get('/calls/history',headers=ah).json()[0]['outgoing'] is True
        assert c.get('/calls/history',headers=oh).json()==[]
        assert c.delete(f'/chats/{cid}/membership',headers=ah).status_code==400
