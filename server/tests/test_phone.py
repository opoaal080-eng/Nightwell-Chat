import app as api
from fastapi.testclient import TestClient


def h(token):
    return {"Authorization": "Bearer " + token}


def test_phone_register_login_privacy_contact_lookup_and_format():
    with TestClient(api.app) as c:
        bad = c.post('/auth/phone/register', json={
            'phone':'+7000000','password':'Strong_Password_123','display_name':'Alice'})
        assert bad.status_code == 422
        reg = c.post('/auth/phone/register',json={
            'phone':'+7 (999) 111-22-33','password':'Strong_Password_123',
            'display_name':'Alice','discoverable':False})
        assert reg.status_code == 201,reg.text
        alice=reg.json()
        assert alice['user']['display_name']=='Alice'
        assert c.get('/me/phone',headers=h(alice['access_token'])).json() == {
            'phone':'+79991112233','discoverable':False}
        duplicate = c.post('/auth/phone/register',json={
            'phone':'89991112233','password':'Strong_Password_123','display_name':'Other'})
        assert duplicate.status_code == 409
        incorrect=c.post('/auth/phone/login',json={'phone':'89991112233','password':'wrongpassword'})
        assert incorrect.status_code == 401
        assert c.post('/auth/phone/login',json={'phone':'+79998889999','password':'wrongpassword'}).status_code == 401
        logged=c.post('/auth/phone/login',json={'phone':'89991112233','password':'Strong_Password_123'})
        assert logged.status_code == 200
        assert logged.json()['user']['id']==alice['user']['id']
        bob=c.post('/auth/register',json={'username':'phone_bob','password':'safe-password-123','display_name':'Bob'}).json()
        auth=h(bob['access_token'])
        assert c.get('/users/by-phone',params={'phone':'+79991112233'}).status_code == 401
        assert c.get('/users/by-phone',params={'phone':'+79991112233'},headers=auth).json() is None
        assert c.patch('/me/phone/visibility',headers=h(alice['access_token']),json={'discoverable':True}).status_code==200
        match=c.get('/users/by-phone',params={'phone':'+79991112233'},headers=auth).json()
        assert match['id']==alice['user']['id'] and 'phone' not in match
        assert c.get('/users/by-phone',params={'phone':'+79991112233'},headers=h(alice['access_token'])).json() is None
        assert c.patch('/me/phone/visibility',headers=h(alice['access_token']),json={'discoverable':False}).status_code==200
        assert c.get('/users/by-phone',params={'phone':'+79991112233'},headers=auth).json() is None


def test_legacy_link_requires_password_preserves_user_and_chats():
    with TestClient(api.app) as c:
        old=c.post('/auth/register',json={'username':'existing_one','password':'safe-password-123','display_name':'Existing'}).json()
        headers=h(old['access_token'])
        no_auth=c.post('/me/phone/link',json={'phone':'+79995556677','password':'safe-password-123'})
        assert no_auth.status_code==401
        invalid=c.post('/me/phone/link',headers=headers,json={'phone':'+79995556677','password':'wrongpassword'})
        assert invalid.status_code==401
        assert c.get('/me/phone',headers=headers).json()['phone'] is None
        good=c.post('/me/phone/link',headers=headers,json={'phone':'+79995556677','password':'safe-password-123','discoverable':True})
        assert good.status_code==200,good.text
        assert c.get('/me/phone',headers=headers).json()['discoverable'] is True
        assert c.post('/auth/login',json={'username':'existing_one','password':'safe-password-123'}).status_code==200
        phone_login=c.post('/auth/phone/login',json={'phone':'+79995556677','password':'safe-password-123'})
        assert phone_login.status_code==200
        assert phone_login.json()['user']['id']==old['user']['id']
        other=c.post('/auth/register',json={'username':'other_one','password':'safe-password-123','display_name':'Other'}).json()
        conflict=c.post('/me/phone/link',headers=h(other['access_token']),json={
            'phone':'+79995556677','password':'safe-password-123'})
        assert conflict.status_code==409


def test_rate_limit_phone_login():
    with TestClient(api.app) as c:
        for _ in range(8):
            assert c.post('/auth/phone/login',json={'phone':'+79990001122','password':'not_a_secret'}).status_code==401
        assert c.post('/auth/phone/login',json={'phone':'+79990001122','password':'not_a_secret'}).status_code==429


def test_legacy_sms_endpoints_disabled():
    with TestClient(api.app) as c:
        assert c.post('/auth/phone/request',json={'phone':'+79997778899'}).status_code==404
        assert c.post('/auth/phone/verify',json={'phone':'+79997778899','code':'123456'}).status_code==404
