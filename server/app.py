"""Nightwell Chat API, text-messaging MVP. All chat data stays on your server."""
import asyncio
import hashlib
import hmac
import os
import re
import secrets
import sqlite3
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

import jwt
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends, Header, Query
from pydantic import BaseModel, Field

DB_PATH = Path(os.getenv("DB_PATH", "./nightwell_chat.db"))
SECRET = os.getenv("SECRET_KEY", "")
if len(SECRET) < 32 or SECRET.startswith("REPLACE_WITH_"):
    raise RuntimeError("Set SECRET_KEY to a random string of at least 32 characters")

@contextmanager
def db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=15)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA busy_timeout = 15000")
    try:
        yield con
        con.commit()
    finally:
        con.close()

def setup():
    with db() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.executescript("""
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL,
          display_name TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS chats(id INTEGER PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('direct','group')),
          title TEXT NOT NULL DEFAULT '', owner_id INTEGER REFERENCES users(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS members(chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
          user_id INTEGER NOT NULL REFERENCES users(id), role TEXT NOT NULL DEFAULT 'member',
          last_read_id INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(chat_id,user_id));
        CREATE TABLE IF NOT EXISTS direct_pairs(a INTEGER NOT NULL,b INTEGER NOT NULL,
          chat_id INTEGER UNIQUE NOT NULL REFERENCES chats(id) ON DELETE CASCADE, PRIMARY KEY(a,b));
        CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
          sender_id INTEGER NOT NULL REFERENCES users(id), body TEXT NOT NULL, reply_to INTEGER,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, edited_at TEXT, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS idx_messages_chat ON messages(chat_id,id DESC);
        CREATE TABLE IF NOT EXISTS reactions(message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
          user_id INTEGER NOT NULL REFERENCES users(id), emoji TEXT NOT NULL,
          PRIMARY KEY(message_id,user_id,emoji));
        """)

@asynccontextmanager
async def lifespan(app: FastAPI):
    setup()
    yield

app = FastAPI(title="Nightwell Chat", version="0.1.0", lifespan=lifespan)

class Credentials(BaseModel):
    username: str = Field(min_length=3,max_length=24)
    password: str = Field(min_length=8,max_length=256)

class Registration(Credentials):
    display_name: str = Field(min_length=1,max_length=60)

class Profile(BaseModel):
    display_name: str = Field(min_length=1,max_length=60)

class ChatCreate(BaseModel):
    title: str = Field(min_length=1,max_length=80)
    user_ids: list[int] = Field(default_factory=list,max_length=100)

class MessageCreate(BaseModel):
    body: str = Field(min_length=1,max_length=4000)
    reply_to: int | None = None

class ReactionCreate(BaseModel):
    emoji: str = Field(min_length=1,max_length=12)

class MemberCreate(BaseModel):
    user_id: int

class ReadUpdate(BaseModel):
    message_id: int

def hash_pw(pw: str):
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(pw.encode(),salt=salt,n=2**14,r=8,p=1)
    return salt.hex()+":"+digest.hex()

def verify_pw(pw: str, stored: str):
    try:
        salt, digest = stored.split(":",1)
        actual = hashlib.scrypt(pw.encode(),salt=bytes.fromhex(salt),n=2**14,r=8,p=1)
        return hmac.compare_digest(actual,bytes.fromhex(digest))
    except (ValueError,TypeError):
        return False

def token(uid: int):
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub":str(uid),"iat":now,"exp":now+timedelta(days=14)},SECRET,algorithm="HS256")

def identity(raw: str):
    try:
        data = jwt.decode(raw,SECRET,algorithms=["HS256"])
        uid = int(data["sub"])
        with db() as c:
            user = c.execute("SELECT id,username,display_name FROM users WHERE id=?",(uid,)).fetchone()
        if user: return dict(user)
    except (jwt.PyJWTError,ValueError,KeyError):
        pass
    raise HTTPException(401,"Invalid or expired token")

def current(authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401,"Bearer token required")
    return identity(authorization[7:])

def member(c, chat_id, uid):
    row=c.execute("SELECT role FROM members WHERE chat_id=? AND user_id=?",(chat_id,uid)).fetchone()
    if not row: raise HTTPException(403,"You are not a member of this chat")
    return row["role"]

def user_public(row):
    return {k:row[k] for k in ("id","username","display_name")}

# Live socket connections are scoped to one process. Use Redis pub/sub when scaling to multiple workers.
clients: dict[int,set[WebSocket]] = {}

async def notify(ids: list[int], payload: dict):
    for uid in set(ids):
        for ws in list(clients.get(uid,())):
            try: await ws.send_json(payload)
            except Exception: clients.get(uid,set()).discard(ws)

def members(c, chat_id):
    return [r[0] for r in c.execute("SELECT user_id FROM members WHERE chat_id=?",(chat_id,)).fetchall()]

@app.get("/health")
def health(): return {"ok":True,"service":"nightwell-chat"}

@app.post("/auth/register",status_code=201)
def register(data: Registration):
    username=data.username.casefold().strip()
    if not re.fullmatch(r"[a-z0-9_]{3,24}",username):
        raise HTTPException(422,"Username: 3-24 Latin letters, digits or underscores")
    if not data.display_name.strip(): raise HTTPException(422,"Display name cannot be blank")
    with db() as c:
        try:
            cur=c.execute("INSERT INTO users(username,display_name,password_hash) VALUES(?,?,?)",
                  (username,data.display_name.strip(),hash_pw(data.password)))
        except sqlite3.IntegrityError:
            raise HTTPException(409,"Username is taken")
        uid=cur.lastrowid
    return {"access_token":token(uid),"token_type":"bearer","user":{"id":uid,"username":username,"display_name":data.display_name.strip()}}

@app.post("/auth/login")
def login(data: Credentials):
    with db() as c:
        row=c.execute("SELECT * FROM users WHERE username=?",(data.username.casefold().strip(),)).fetchone()
    if not row or not verify_pw(data.password,row["password_hash"]):
        raise HTTPException(401,"Invalid credentials")
    return {"access_token":token(row["id"]),"token_type":"bearer","user":user_public(row)}

@app.get("/me")
def me(user=Depends(current)): return user

@app.patch("/me")
def update_me(body: Profile,user=Depends(current)):
    if not body.display_name.strip(): raise HTTPException(422,"Display name cannot be blank")
    with db() as c:
        c.execute("UPDATE users SET display_name=? WHERE id=?",(body.display_name.strip(),user["id"]))
    return {**user,"display_name":body.display_name.strip()}

@app.get("/users")
def search_users(q: str = Query(min_length=1,max_length=50),user=Depends(current)):
    with db() as c:
        rows=c.execute("SELECT id,username,display_name FROM users WHERE id<>? AND (username LIKE ? OR display_name LIKE ?) ORDER BY username LIMIT 30",
          (user["id"],"%"+q+"%","%"+q+"%")).fetchall()
    return [dict(x) for x in rows]

def chat_view(c, row, uid):
    cid=row["id"]
    other=c.execute("SELECT u.id,u.username,u.display_name FROM users u JOIN members m ON u.id=m.user_id WHERE m.chat_id=? AND m.user_id<>? LIMIT 1",(cid,uid)).fetchone() if row["kind"]=="direct" else None
    last=c.execute("SELECT id,body,sender_id,created_at FROM messages WHERE chat_id=? ORDER BY id DESC LIMIT 1",(cid,)).fetchone()
    read=c.execute("SELECT last_read_id FROM members WHERE chat_id=? AND user_id=?",(cid,uid)).fetchone()
    unread=c.execute("SELECT COUNT(*) FROM messages WHERE chat_id=? AND id>? AND sender_id<>?",(cid,read[0] if read else 0,uid)).fetchone()[0]
    return {"id":cid,"kind":row["kind"],"title":other["display_name"] if other else row["title"],
      "other_user":dict(other) if other else None,"owner_id":row["owner_id"],"unread":unread,"last_message":dict(last) if last else None}

@app.get("/chats")
def get_chats(user=Depends(current)):
    with db() as c:
        rows=c.execute("SELECT c.* FROM chats c JOIN members m ON m.chat_id=c.id WHERE m.user_id=? ORDER BY COALESCE((SELECT MAX(id) FROM messages WHERE chat_id=c.id),0) DESC,c.id DESC",(user["id"],)).fetchall()
        return [chat_view(c,row,user["id"]) for row in rows]

@app.post("/chats/direct/{other_id}")
async def direct(other_id:int,user=Depends(current)):
    uid=user["id"]
    if other_id==uid: raise HTTPException(400,"Cannot chat with yourself")
    a,b=sorted((uid,other_id))
    with db() as c:
        if not c.execute("SELECT id FROM users WHERE id=?",(other_id,)).fetchone(): raise HTTPException(404,"User not found")
        row=c.execute("SELECT chat_id FROM direct_pairs WHERE a=? AND b=?",(a,b)).fetchone()
        if row: cid=row[0]
        else:
            cid=c.execute("INSERT INTO chats(kind,owner_id) VALUES('direct',?)",(uid,)).lastrowid
            c.executemany("INSERT INTO members(chat_id,user_id) VALUES(?,?)",[(cid,uid),(cid,other_id)])
            c.execute("INSERT INTO direct_pairs(a,b,chat_id) VALUES(?,?,?)",(a,b,cid))
        chat=chat_view(c,c.execute("SELECT * FROM chats WHERE id=?",(cid,)).fetchone(),uid)
    await notify([other_id],{"type":"chats_changed"})
    return chat

@app.post("/chats/groups",status_code=201)
async def group(payload:ChatCreate,user=Depends(current)):
    if not payload.title.strip(): raise HTTPException(422,"Group title cannot be blank")
    uid=user["id"]
    people=set(payload.user_ids)|{uid}
    with db() as c:
        found={r[0] for r in c.execute("SELECT id FROM users WHERE id IN ("+",".join("?" for _ in people)+")",tuple(people))}
        if found!=people: raise HTTPException(404,"One or more users not found")
        cid=c.execute("INSERT INTO chats(kind,title,owner_id) VALUES('group',?,?)",(payload.title.strip(),uid)).lastrowid
        c.executemany("INSERT INTO members(chat_id,user_id,role) VALUES(?,?,?)",[(cid,x,"owner" if x==uid else "member") for x in people])
        chat=chat_view(c,c.execute("SELECT * FROM chats WHERE id=?",(cid,)).fetchone(),uid)
    await notify(list(people),{"type":"chats_changed"})
    return chat

@app.post("/chats/{chat_id}/members")
async def add_member(chat_id:int,body:MemberCreate,user=Depends(current)):
    with db() as c:
        if member(c,chat_id,user["id"])!="owner": raise HTTPException(403,"Only owner can add members")
        if c.execute("SELECT kind FROM chats WHERE id=?",(chat_id,)).fetchone()[0]!="group": raise HTTPException(400,"Not a group")
        if not c.execute("SELECT id FROM users WHERE id=?",(body.user_id,)).fetchone(): raise HTTPException(404,"User not found")
        c.execute("INSERT OR IGNORE INTO members(chat_id,user_id) VALUES(?,?)",(chat_id,body.user_id))
        ids=members(c,chat_id)
    await notify(ids,{"type":"chats_changed"})
    return {"ok":True}

def message_view(c, row):
    sender=c.execute("SELECT username,display_name FROM users WHERE id=?",(row["sender_id"],)).fetchone()
    reactions=c.execute("SELECT emoji,COUNT(*) AS count FROM reactions WHERE message_id=? GROUP BY emoji",(row["id"],)).fetchall()
    return {**dict(row),"body":"" if row["deleted"] else row["body"],"sender_name":sender["display_name"],"reactions":[dict(x) for x in reactions]}

@app.get("/chats/{chat_id}/messages")
def get_messages(chat_id:int,before:int|None=None,limit:int=Query(50,ge=1,le=100),user=Depends(current)):
    with db() as c:
        member(c,chat_id,user["id"])
        rows=c.execute("SELECT * FROM messages WHERE chat_id=? AND id<? ORDER BY id DESC LIMIT ?",(chat_id,before or 2**63-1,limit)).fetchall()
        return [message_view(c,r) for r in reversed(rows)]

@app.post("/chats/{chat_id}/messages",status_code=201)
async def send_message(chat_id:int,payload:MessageCreate,user=Depends(current)):
    if not payload.body.strip(): raise HTTPException(422,"Message cannot be blank")
    with db() as c:
        member(c,chat_id,user["id"])
        if payload.reply_to and not c.execute("SELECT id FROM messages WHERE id=? AND chat_id=?",(payload.reply_to,chat_id)).fetchone():
            raise HTTPException(400,"Reply message not in chat")
        mid=c.execute("INSERT INTO messages(chat_id,sender_id,body,reply_to) VALUES(?,?,?,?)",(chat_id,user["id"],payload.body.strip(),payload.reply_to)).lastrowid
        msg=message_view(c,c.execute("SELECT * FROM messages WHERE id=?",(mid,)).fetchone())
        ids=members(c,chat_id)
    await notify(ids,{"type":"message","chat_id":chat_id,"message":msg})
    return msg

def own_message(c,mid,uid):
    row=c.execute("SELECT * FROM messages WHERE id=?",(mid,)).fetchone()
    if not row: raise HTTPException(404,"Message not found")
    member(c,row["chat_id"],uid)
    if row["sender_id"]!=uid: raise HTTPException(403,"Not your message")
    return row

@app.patch("/messages/{message_id}")
async def edit_message(message_id:int,payload:MessageCreate,user=Depends(current)):
    if not payload.body.strip(): raise HTTPException(422,"Message cannot be blank")
    with db() as c:
        row=own_message(c,message_id,user["id"])
        if row["deleted"]: raise HTTPException(400,"Deleted message")
        c.execute("UPDATE messages SET body=?,edited_at=CURRENT_TIMESTAMP WHERE id=?",(payload.body.strip(),message_id))
        msg=message_view(c,c.execute("SELECT * FROM messages WHERE id=?",(message_id,)).fetchone())
        ids=members(c,row["chat_id"])
    await notify(ids,{"type":"message_updated","chat_id":row["chat_id"],"message":msg})
    return msg

@app.delete("/messages/{message_id}")
async def delete_message(message_id:int,user=Depends(current)):
    with db() as c:
        row=own_message(c,message_id,user["id"])
        c.execute("UPDATE messages SET deleted=1,body='' WHERE id=?",(message_id,))
        ids=members(c,row["chat_id"])
    await notify(ids,{"type":"message_deleted","chat_id":row["chat_id"],"message_id":message_id})
    return {"ok":True}

@app.post("/messages/{message_id}/reactions")
async def toggle_reaction(message_id:int,payload:ReactionCreate,user=Depends(current)):
    with db() as c:
        row=c.execute("SELECT chat_id FROM messages WHERE id=? AND deleted=0",(message_id,)).fetchone()
        if not row: raise HTTPException(404,"Message not found")
        member(c,row["chat_id"],user["id"])
        match=c.execute("SELECT 1 FROM reactions WHERE message_id=? AND user_id=? AND emoji=?",(message_id,user["id"],payload.emoji)).fetchone()
        if match: c.execute("DELETE FROM reactions WHERE message_id=? AND user_id=? AND emoji=?",(message_id,user["id"],payload.emoji))
        else: c.execute("INSERT INTO reactions(message_id,user_id,emoji) VALUES(?,?,?)",(message_id,user["id"],payload.emoji))
        msg=message_view(c,c.execute("SELECT * FROM messages WHERE id=?",(message_id,)).fetchone())
        ids=members(c,row["chat_id"])
    await notify(ids,{"type":"message_updated","chat_id":row["chat_id"],"message":msg})
    return msg

@app.post("/chats/{chat_id}/read")
async def mark_read(chat_id:int,body:ReadUpdate,user=Depends(current)):
    with db() as c:
        member(c,chat_id,user["id"])
        row=c.execute("SELECT COALESCE(MAX(id),0) FROM messages WHERE chat_id=?",(chat_id,)).fetchone()
        safe_id=max(0,min(body.message_id,row[0]))
        previous=c.execute("SELECT last_read_id FROM members WHERE chat_id=? AND user_id=?",(chat_id,user["id"])).fetchone()[0]
        if safe_id <= previous: return {"ok":True}
        c.execute("UPDATE members SET last_read_id=? WHERE chat_id=? AND user_id=?",(safe_id,chat_id,user["id"]))
        ids=members(c,chat_id)
    await notify(ids,{"type":"read","chat_id":chat_id,"user_id":user["id"],"message_id":safe_id})
    return {"ok":True}

@app.websocket("/ws")
async def websocket_endpoint(ws:WebSocket):
    auth=ws.headers.get("authorization","")
    try: user=identity(auth[7:] if auth.startswith("Bearer ") else "")
    except HTTPException:
        await ws.close(code=1008)
        return
    uid=user["id"]
    await ws.accept()
    clients.setdefault(uid,set()).add(ws)
    try:
        await ws.send_json({"type":"connected"})
        while True:
            # Client sends ping every 25s; no sensitive commands accepted over WS.
            msg=await ws.receive_json()
            if msg.get("type")=="ping": await ws.send_json({"type":"pong"})
    except (WebSocketDisconnect,RuntimeError,ValueError):
        pass
    finally:
        clients.get(uid,set()).discard(ws)
