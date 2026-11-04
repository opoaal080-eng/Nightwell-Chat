"""Regression test for peers joining signaling before a ringing call is accepted."""
from fastapi.testclient import TestClient
from app import app, call_ticket


def test_accept_notifies_two_existing_websocket_peers():
    with TestClient(app) as client:
        def signup(username):
            result = client.post("/auth/register", json={
                "username": username,
                "password": "test-password-123",
                "display_name": username,
            })
            assert result.status_code == 201, result.text
            data = result.json()
            return data["user"]["id"], {"Authorization": "Bearer " + data["access_token"]}

        caller_id, caller_auth = signup("early_signal_caller")
        callee_id, callee_auth = signup("early_signal_callee")
        assert client.post(f"/chats/direct/{callee_id}", headers=caller_auth).status_code == 200
        call = client.post(f"/calls/direct/{callee_id}", headers=caller_auth)
        assert call.status_code == 201
        cid = call.json()["id"]

        with client.websocket_connect(f"/calls/{cid}/signal?ticket={call_ticket(cid, caller_id)}") as caller:
            assert caller.receive_json()["type"] == "connected"
            with client.websocket_connect(f"/calls/{cid}/signal?ticket={call_ticket(cid, callee_id)}") as callee:
                assert callee.receive_json()["type"] == "connected"

                # Both sockets are connected before the callee presses Answer.
                accepted = client.post(f"/calls/{cid}/accept", headers=callee_auth)
                assert accepted.status_code == 200
                assert caller.receive_json()["type"] == "peer_ready"
                assert callee.receive_json()["type"] == "peer_ready"

                caller.send_json({"type": "offer", "data": {"type": "offer", "sdp": "v=0\\r\\n"}})
                assert callee.receive_json()["type"] == "offer"
                callee.send_json({"type": "answer", "data": {"type": "answer", "sdp": "v=0\\r\\n"}})
                assert caller.receive_json()["type"] == "answer"
                # A microphone failure on Android is relayed immediately to iPhone.
                callee.send_json({"type": "media_error", "data": {"code": "NotReadableError"}})
                problem = caller.receive_json()
                assert problem == {"type": "peer_media_error", "data": {"code": "NotReadableError"}}

                # The other phone must be told if the microphone becomes available.
                callee.send_json({"type": "media_ready"})
                assert caller.receive_json()["type"] == "peer_media_ready"

