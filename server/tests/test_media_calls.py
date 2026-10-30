"""Smoke tests for avatar/media authorization and call state on the real API."""
from io import BytesIO
from PIL import Image
from fastapi.testclient import TestClient
from app import app


def make_user(client, name):
    response = client.post('/auth/register',json={'username':name, 'password':'testing-password-123', 'display_name':name})
    assert response.status_code == 201, response.text
    item=response.json()
    return item['user']['id'], {'Authorization':'Bearer '+item['access_token']}


def image_bytes():
    data=BytesIO()
    Image.new('RGB',(32,32),color=(240,240,240)).save(data,'PNG')
    return data.getvalue()


def test_avatar_and_attachments_are_authenticated_and_chat_scoped():
    with TestClient(app) as c:
        aid, ah=make_user(c,'mediaalice')
        bid, bh=make_user(c,'mediabob')
        _, oh=make_user(c,'mediaoutsider')
        chat=c.post(f'/chats/direct/{bid}',headers=ah)
        assert chat.status_code == 200,chat.text
        chat_id=chat.json()['id']
        avatar=c.post('/me/avatar',headers=ah,files={'file':('my.png',image_bytes(),'image/png')})
        assert avatar.status_code == 200,avatar.text
        assert c.get(f'/users/{aid}/avatar').status_code == 401
        returned=c.get(f'/users/{aid}/avatar',headers=bh)
        assert returned.status_code == 200 and returned.headers['content-type'].startswith('image/jpeg')
        uploaded=c.post(f'/chats/{chat_id}/attachments',headers=ah,files={'file':('photo.png',image_bytes(),'image/png')},data={'caption':'hey'})
        assert uploaded.status_code == 201,uploaded.text
        message=uploaded.json()
        assert message['attachment']['content_type']=='image/jpeg'
        file_id=message['attachment']['id']
        assert c.get(f'/attachments/{file_id}',headers=oh).status_code == 403
        assert c.get(f'/attachments/{file_id}',headers=bh).status_code == 200
        bad=c.post(f'/chats/{chat_id}/attachments',headers=ah,files={'file':('bad.exe',b'MZ','application/octet-stream')})
        assert bad.status_code == 415


def test_voice_call_accept_end_and_access():
    with TestClient(app) as c:
        aid,ah=make_user(c,'callalice')
        bid,bh=make_user(c,'callbob')
        _,oh=make_user(c,'calloutsider')
        assert c.post(f'/calls/direct/{bid}',headers=ah).status_code == 404
        assert c.post(f'/chats/direct/{bid}',headers=ah).status_code == 200
        invited=c.post(f'/calls/direct/{bid}',headers=ah)
        assert invited.status_code == 201, invited.text
        call_id=invited.json()['id']
        pending=c.get('/calls/pending',headers=bh)
        assert pending.status_code == 200 and pending.json()[0]['id']==call_id
        assert c.post(f'/calls/{call_id}/accept',headers=oh).status_code == 404
        accepted=c.post(f'/calls/{call_id}/accept',headers=bh)
        assert accepted.status_code == 200,accepted.text
        assert 'ticket' in accepted.json()
        html=c.get(f'/calls/{call_id}/page')
        assert html.status_code == 200 and 'WebRTC' in html.text
        ended=c.post(f'/calls/{call_id}/end',headers=ah)
        assert ended.status_code == 200
        assert c.post(f'/calls/{call_id}/accept',headers=bh).status_code == 409
