"""Nightwell Chat API, text-messaging MVP. All chat data stays on your server."""
import asyncio
import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time
import io
import uuid
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

import jwt
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends, Header, Query, Request, UploadFile, File, Form
from pydantic import BaseModel, Field
from fastapi.responses import FileResponse, Response
from PIL import Image, ImageOps, UnidentifiedImageError

DB_PATH = Path(os.getenv("DB_PATH", "./nightwell_chat.db"))
MEDIA_DIR = Path(os.getenv("MEDIA_DIR", str(DB_PATH.parent / "media"))).resolve()
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
        # Media and profile data, additive migrations only; no existing messages are removed.
        user_columns={r[1] for r in c.execute("PRAGMA table_info(users)")}
        if "avatar_key" not in user_columns:
            c.execute("ALTER TABLE users ADD COLUMN avatar_key TEXT")
        c.executescript("""
        CREATE TABLE IF NOT EXISTS attachments (
            id INTEGER PRIMARY KEY,
            message_id INTEGER NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
            filename TEXT NOT NULL,
            content_type TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            storage_key TEXT NOT NULL UNIQUE
        );
        """)
        # Backwards-compatible migration: keep all old accounts, chats and messages.
        cols={r[1] for r in c.execute("PRAGMA table_info(users)")}
        if "phone" not in cols:
            c.execute("ALTER TABLE users ADD COLUMN phone TEXT")
        if "phone_discoverable" not in cols:
            c.execute("ALTER TABLE users ADD COLUMN phone_discoverable INTEGER NOT NULL DEFAULT 0")
        c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL")
        c.executescript("""
        CREATE TABLE IF NOT EXISTS phone_auth_attempts(
            id INTEGER PRIMARY KEY, phone_hash TEXT NOT NULL, ip_hash TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_phone_auth_number ON phone_auth_attempts(phone_hash,created_at);
        CREATE INDEX IF NOT EXISTS idx_phone_auth_ip ON phone_auth_attempts(ip_hash,created_at);
        CREATE TABLE IF NOT EXISTS phone_search_log(
            id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_phone_search_user ON phone_search_log(user_id,created_at);
        """)

@asynccontextmanager
async def lifespan(app: FastAPI):
    setup()
    yield

app = FastAPI(title="Nightwell Chat", version="0.2.0", lifespan=lifespan)

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
            user = c.execute("SELECT id,username,display_name,avatar_key FROM users WHERE id=?",(uid,)).fetchone()
        if user: return user_public(user)
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
    return {**{k:row[k] for k in ("id","username","display_name")},
            "has_avatar": bool(row["avatar_key"]) if "avatar_key" in row.keys() else False}

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
        updated = c.execute("SELECT id,username,display_name,avatar_key FROM users WHERE id=?", (user["id"],)).fetchone()
    return user_public(updated)

# Phone/password login and contact discovery. A format check is NOT proof
# of SIM ownership. No SMS, calls or third-party lookup are performed.
class PhonePassword(BaseModel):
    phone: str = Field(min_length=8, max_length=35)
    password: str = Field(min_length=8, max_length=256)

class PhoneRegistration(PhonePassword):
    display_name: str = Field(min_length=1, max_length=60)
    discoverable: bool = False

class PhoneLink(PhonePassword):
    discoverable: bool = False

class PhoneVisibility(BaseModel):
    discoverable: bool


def normalize_phone(value: str) -> str:
    # International E.164 syntax and length check. Does not verify ownership,
    # number allocation, carrier, or ability to receive SMS/calls.
    digits=re.sub(r"[\s()\-]", "", value.strip())
    if re.fullmatch(r"9\d{9}",digits):
        digits="+7"+digits
    elif re.fullmatch(r"8\d{10}",digits):
        digits="+7"+digits[1:]
    elif re.fullmatch(r"7\d{10}",digits):
        digits="+"+digits
    if not re.fullmatch(r"\+[1-9]\d{7,14}",digits):
        raise HTTPException(422,"Неверный формат. Введи номер с кодом страны, например +79991234567")
    if digits.startswith("+7") and (len(digits)!=12 or digits[2] not in "3489"):
        raise HTTPException(422,"Неверный формат российского номера")
    return digits


def _hash_log(value:str) -> str:
    return hmac.new(SECRET.encode(),value.encode(),hashlib.sha256).hexdigest()


def _source(request:Request) -> str:
    ip=request.client.host if request.client else "unknown"
    if ip in ("127.0.0.1", "::1"):
        forwarded=request.headers.get("x-forwarded-for", "").split(",",1)[0].strip()
        if forwarded: ip=forwarded[:80]
    return ip


def auth_limit(c,request:Request,phone:str) -> None:
    # Persist login throttling across workers/restarts. Store only HMACs of
    # numbers and IPs, no plain text phone/IP in rate-limit records.
    now=int(time.time())
    number_hash=_hash_log(phone)
    ip_hash=_hash_log(_source(request))
    c.execute("BEGIN IMMEDIATE")
    c.execute("DELETE FROM phone_auth_attempts WHERE created_at<?",(now-86400,))
    attempts=c.execute("SELECT COUNT(*) FROM phone_auth_attempts WHERE phone_hash=? AND created_at>?",
        (number_hash,now-900)).fetchone()[0]
    ip_attempts=c.execute("SELECT COUNT(*) FROM phone_auth_attempts WHERE ip_hash=? AND created_at>?",
        (ip_hash,now-900)).fetchone()[0]
    if attempts>=8 or ip_attempts>=60:
        raise HTTPException(429,"Слишком много попыток. Повтори через 15 минут")
    c.execute("INSERT INTO phone_auth_attempts(phone_hash,ip_hash,created_at) VALUES(?,?,?)",
        (number_hash,ip_hash,now))


@app.post("/auth/phone/register",status_code=201)
def register_by_phone(data:PhoneRegistration,request:Request):
    phone=normalize_phone(data.phone)
    name=data.display_name.strip()
    if not name: raise HTTPException(422,"Имя не может быть пустым")
    with db() as c:
        auth_limit(c,request,phone)
        try:
            # Internal usernames are random and never based on phone numbers.
            uid=c.execute("INSERT INTO users(username,display_name,password_hash,phone,phone_discoverable) VALUES(?,?,?,?,?)",
                ("nw_"+secrets.token_hex(10),name,hash_pw(data.password),phone,int(data.discoverable))).lastrowid
        except sqlite3.IntegrityError:
            raise HTTPException(409,"Номер уже зарегистрирован")
        user=c.execute("SELECT id,username,display_name,avatar_key FROM users WHERE id=?",(uid,)).fetchone()
    return {"access_token":token(uid),"token_type":"bearer","user":user_public(user)}


@app.post("/auth/phone/login")
def login_by_phone(data:PhonePassword,request:Request):
    phone=normalize_phone(data.phone)
    with db() as c:
        auth_limit(c,request,phone)
        user=c.execute("SELECT id,username,display_name,password_hash FROM users WHERE phone=?",(phone,)).fetchone()
    # Generic response, even when the number is not registered.
    if not user or not verify_pw(data.password,user["password_hash"]):
        raise HTTPException(401,"Неверный номер или пароль")
    return {"access_token":token(user["id"]),"token_type":"bearer","user":user_public(user)}


@app.post("/me/phone/link")
def link_phone(data:PhoneLink,user=Depends(current)):
    phone=normalize_phone(data.phone)
    with db() as c:
        old=c.execute("SELECT password_hash FROM users WHERE id=?",(user["id"],)).fetchone()
        if not old or not verify_pw(data.password,old["password_hash"]):
            raise HTTPException(401,"Неверный пароль аккаунта")
        try:
            c.execute("UPDATE users SET phone=?,phone_discoverable=? WHERE id=?",
                (phone,int(data.discoverable),user["id"]))
        except sqlite3.IntegrityError:
            raise HTTPException(409,"Номер уже зарегистрирован в другом аккаунте")
    return {"ok":True}


@app.get("/me/phone")
def my_phone(user=Depends(current)):
    with db() as c:
        row=c.execute("SELECT phone,phone_discoverable FROM users WHERE id=?",(user["id"],)).fetchone()
    return {"phone":row["phone"],"discoverable":bool(row["phone_discoverable"])}


@app.patch("/me/phone/visibility")
def change_phone_visibility(data:PhoneVisibility,user=Depends(current)):
    with db() as c:
        c.execute("UPDATE users SET phone_discoverable=? WHERE id=?",(int(data.discoverable),user["id"]))
    return {"ok":True}


@app.get("/users/by-phone")
def search_by_phone(phone:str=Query(min_length=8,max_length=35),user=Depends(current)):
    number=normalize_phone(phone)
    now=int(time.time())
    with db() as c:
        c.execute("BEGIN IMMEDIATE")
        c.execute("DELETE FROM phone_search_log WHERE created_at<?",(now-86400,))
        minute=c.execute("SELECT COUNT(*) FROM phone_search_log WHERE user_id=? AND created_at>?",(user["id"],now-60)).fetchone()[0]
        day=c.execute("SELECT COUNT(*) FROM phone_search_log WHERE user_id=?",(user["id"],)).fetchone()[0]
        if minute>=10 or day>=100:
            raise HTTPException(429,"Слишком много поисковых запросов")
        c.execute("INSERT INTO phone_search_log(user_id,created_at) VALUES(?,?)",(user["id"],now))
        found=c.execute("SELECT id,username,display_name,avatar_key FROM users WHERE phone=? AND phone_discoverable=1 AND id<>?",(number,user["id"])).fetchone()
        return user_public(found) if found else None


# Attachments are stored outside the web root and require bearer auth on every read.
MAX_FILE_SIZE = 15 * 1024 * 1024
MAX_AVATAR_SIZE = 6 * 1024 * 1024
ALLOWED_SUFFIXES = {".jpg":"image/jpeg", ".jpeg":"image/jpeg", ".png":"image/png",
    ".webp":"image/webp", ".gif":"image/gif", ".pdf":"application/pdf",
    ".txt":"text/plain", ".zip":"application/zip", ".docx":"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xlsx":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}

def attachment_view(c, mid: int):
    row = c.execute("SELECT id,filename,content_type,byte_size FROM attachments WHERE message_id=?", (mid,)).fetchone()
    return dict(row) if row else None

async def limited_read(file: UploadFile, max_bytes: int) -> bytes:
    data = await file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(413, "File is too large")
    if not data:
        raise HTTPException(422, "Empty file")
    return data

def persist_bytes(subdir: str, content: bytes, suffix: str) -> str:
    key = f"{subdir}/{uuid.uuid4().hex}{suffix}"
    location = MEDIA_DIR / key
    location.parent.mkdir(parents=True, exist_ok=True)
    with location.open("xb") as handle:
        handle.write(content)
    return key

def clean_filename(name: str) -> str:
    name = name.replace("\\", "/").split("/")[-1].strip().replace("\x00", "")
    return name[:120] if name else "file"

def verified_media(data: bytes, suffix: str) -> tuple[bytes, str, str]:
    # All uploaded images are re-encoded, removing EXIF/GPS and active content.
    if suffix in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        try:
            with Image.open(io.BytesIO(data)) as original:
                original.verify()
            with Image.open(io.BytesIO(data)) as original:
                if original.width * original.height > 24_000_000: raise HTTPException(413, "Image too large")
                img = ImageOps.exif_transpose(original)
                img.thumbnail((2400, 2400))
                output = io.BytesIO()
                img.convert("RGB").save(output, format="JPEG", quality=85, optimize=True)
                return output.getvalue(), ".jpg", "image/jpeg"
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
            raise HTTPException(422, "Invalid image")
    if suffix == ".pdf" and not data.startswith(b"%PDF-"):
        raise HTTPException(422, "Invalid PDF")
    if suffix in {".zip", ".docx", ".xlsx"} and not data.startswith(b"PK\x03\x04"):
        raise HTTPException(422, "Invalid ZIP/document")
    if suffix == ".txt":
        try: data.decode("utf-8")
        except UnicodeError: raise HTTPException(422, "Text file must be UTF-8")
    return data, suffix, ALLOWED_SUFFIXES[suffix]

@app.post("/me/avatar")
async def set_avatar(file: UploadFile = File(...), user=Depends(current)):
    raw = await limited_read(file, MAX_AVATAR_SIZE)
    try:
        with Image.open(io.BytesIO(raw)) as original:
            original.verify()
        with Image.open(io.BytesIO(raw)) as original:
            if original.width * original.height > 24_000_000: raise HTTPException(413, "Image too large")
            avatar = ImageOps.exif_transpose(original).convert("RGB")
            avatar.thumbnail((512,512))
            encoded = io.BytesIO()
            avatar.save(encoded, "JPEG", quality=85, optimize=True)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(422,"Invalid image")
    key = persist_bytes("avatars", encoded.getvalue(), ".jpg")
    with db() as c:
        old = c.execute("SELECT avatar_key FROM users WHERE id=?", (user["id"],)).fetchone()
        c.execute("UPDATE users SET avatar_key=? WHERE id=?", (key,user["id"]))
    if old and old[0]: (MEDIA_DIR / old[0]).unlink(missing_ok=True)
    return {"ok": True}

@app.delete("/me/avatar")
def delete_avatar(user=Depends(current)):
    with db() as c:
        old = c.execute("SELECT avatar_key FROM users WHERE id=?", (user["id"],)).fetchone()
        c.execute("UPDATE users SET avatar_key=NULL WHERE id=?",(user["id"],))
    if old and old[0]: (MEDIA_DIR / old[0]).unlink(missing_ok=True)
    return {"ok":True}

@app.get("/users/{user_id}/avatar")
def get_avatar(user_id:int, user=Depends(current)):
    with db() as c:
        row = c.execute("SELECT avatar_key FROM users WHERE id=?", (user_id,)).fetchone()
    if not row or not row[0]: raise HTTPException(404,"Avatar not found")
    file = MEDIA_DIR / row[0]
    if not file.is_file(): raise HTTPException(404,"Avatar file missing")
    return FileResponse(file,media_type="image/jpeg",headers={"Cache-Control":"private, no-store", "X-Content-Type-Options":"nosniff"})

@app.post("/chats/{chat_id}/attachments",status_code=201)
async def send_attachment(chat_id: int, file: UploadFile = File(...), caption: str = Form(""), user=Depends(current)):
    with db() as c: member(c,chat_id,user["id"])
    suffix = Path(clean_filename(file.filename or "file")).suffix.lower()
    if suffix not in ALLOWED_SUFFIXES: raise HTTPException(415,"Unsupported file type")
    if len(caption) > 4000: raise HTTPException(422,"Caption too long")
    raw = await limited_read(file, MAX_FILE_SIZE)
    content, suffix, mime = verified_media(raw, suffix)
    name = clean_filename(file.filename or "file")
    if mime == "image/jpeg": name = Path(name).stem[:110] + ".jpg"
    key = persist_bytes("attachments", content, suffix)
    try:
        with db() as c:
            member(c,chat_id,user["id"])
            mid = c.execute("INSERT INTO messages(chat_id,sender_id,body) VALUES(?,?,?)",
                (chat_id,user["id"],caption.strip())).lastrowid
            c.execute("INSERT INTO attachments(message_id,filename,content_type,byte_size,storage_key) VALUES(?,?,?,?,?)",
                (mid,name,mime,len(content),key))
            result = message_view(c,c.execute("SELECT * FROM messages WHERE id=?",(mid,)).fetchone())
            ids = members(c,chat_id)
    except Exception:
        (MEDIA_DIR / key).unlink(missing_ok=True)
        raise
    await notify(ids,{"type":"message","chat_id":chat_id,"message":result})
    return result

@app.get("/attachments/{attachment_id}")
def get_attachment(attachment_id:int, user=Depends(current)):
    with db() as c:
        row = c.execute("""SELECT a.*,m.chat_id,m.deleted FROM attachments a
          JOIN messages m ON m.id=a.message_id WHERE a.id=?""",(attachment_id,)).fetchone()
        if not row or row["deleted"]: raise HTTPException(404,"File not found")
        member(c,row["chat_id"],user["id"])
    path = MEDIA_DIR / row["storage_key"]
    if not path.is_file(): raise HTTPException(404,"File missing")
    # Always a safe filename; authorization already checked above.
    return FileResponse(path,media_type=row["content_type"],filename=row["filename"],
        content_disposition_type="inline" if row["content_type"].startswith("image/") else "attachment",
        headers={"Cache-Control":"private, no-store", "X-Content-Type-Options":"nosniff"})

@app.get("/users")
def search_users(q: str = Query(min_length=1,max_length=50),user=Depends(current)):
    with db() as c:
        rows=c.execute("SELECT id,username,display_name,avatar_key FROM users WHERE id<>? AND (username LIKE ? OR display_name LIKE ?) ORDER BY username LIMIT 30",
          (user["id"],"%"+q+"%","%"+q+"%")).fetchall()
    return [dict(x) for x in rows]

def chat_view(c, row, uid):
    cid=row["id"]
    other=c.execute("SELECT u.id,u.username,u.display_name,u.avatar_key FROM users u JOIN members m ON u.id=m.user_id WHERE m.chat_id=? AND m.user_id<>? LIMIT 1",(cid,uid)).fetchone() if row["kind"]=="direct" else None
    last=c.execute("SELECT id,body,sender_id,created_at FROM messages WHERE chat_id=? ORDER BY id DESC LIMIT 1",(cid,)).fetchone()
    read=c.execute("SELECT last_read_id FROM members WHERE chat_id=? AND user_id=?",(cid,uid)).fetchone()
    unread=c.execute("SELECT COUNT(*) FROM messages WHERE chat_id=? AND id>? AND sender_id<>?",(cid,read[0] if read else 0,uid)).fetchone()[0]
    return {"id":cid,"kind":row["kind"],"title":other["display_name"] if other else row["title"],
      "other_user":user_public(other) if other else None,"owner_id":row["owner_id"],"unread":unread,"last_message":dict(last) if last else None}

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
    return {**dict(row),"body":"" if row["deleted"] else row["body"],"sender_name":sender["display_name"],"attachment": attachment_view(c,row["id"]) if not row["deleted"] else None,"reactions":[dict(x) for x in reactions]}

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
