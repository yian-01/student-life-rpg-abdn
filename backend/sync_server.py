"""V1 snapshot API. Run behind the HTTPS proxy in compose.yaml."""

import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import sqlite3
import time
from contextlib import closing
from pathlib import Path

MAX_SNAPSHOT = 64 * 1024 * 1024
SESSION_SECONDS = 90 * 24 * 60 * 60
EMAIL = re.compile(r"[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+")
HEX_ID = re.compile(r"[0-9a-f]{32}")
TOKEN = re.compile(r"Bearer ([A-Za-z0-9_-]{43})")
REVISION = re.compile(r'"(0|[1-9][0-9]{0,14})"')
SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL,
    salt BLOB NOT NULL, password_hash BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash BLOB PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
    expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS snapshots (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id),
    revision INTEGER NOT NULL, data BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS uploads (
    account_id TEXT NOT NULL REFERENCES accounts(id), request_id TEXT NOT NULL,
    revision INTEGER NOT NULL, digest BLOB NOT NULL,
    PRIMARY KEY (account_id, request_id)
);
CREATE TABLE IF NOT EXISTS auth_limits (
    bucket TEXT NOT NULL, window INTEGER NOT NULL, attempts INTEGER NOT NULL,
    PRIMARY KEY (bucket, window)
);
"""


class ApiError(Exception):
    def __init__(self, status, code):
        self.status = status
        self.code = code


def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=salt, n=2**16, r=8, p=2,
                          maxmem=80 * 1024 * 1024, dklen=32)


def token_hash(token):
    return hashlib.sha256(token.encode("ascii")).digest()


def body(environ, limit):
    length_text = environ.get("CONTENT_LENGTH") or ""
    if not re.fullmatch(r"[0-9]{1,10}", length_text):
        raise ApiError("411 Length Required", "length_required")
    length = int(length_text)
    if length > limit:
        raise ApiError("413 Payload Too Large", "too_large")
    data = environ["wsgi.input"].read(length)
    if len(data) != length:
        raise ApiError("400 Bad Request", "bad_body")
    return data


def json_object(raw):
    try:
        value = json.loads(raw.decode("utf-8"))
        if isinstance(value, dict):
            return value
    except (ValueError, RecursionError):
        pass
    raise ApiError("400 Bad Request", "bad_json")


def checked_snapshot(raw):
    envelope = json_object(raw)
    payload = envelope.get("payload")
    checksum = envelope.get("sha256")
    if (set(envelope) != {"format", "version", "payload", "sha256"}
            or envelope["format"] != "student-life-backup"
            or type(envelope["version"]) is not int or envelope["version"] != 1
            or not isinstance(payload, str) or not isinstance(checksum, str)):
        raise ApiError("400 Bad Request", "invalid_snapshot")
    try:
        digest = hashlib.sha256(payload.encode()).hexdigest()
    except UnicodeError as error:
        raise ApiError("400 Bad Request", "invalid_snapshot") from error
    if digest != checksum:
        raise ApiError("400 Bad Request", "invalid_snapshot")
    snapshot = json_object(payload.encode())
    if (set(snapshot) != {"createdAt", "campus", "tasks"}
            or not all(isinstance(item, str) and item for item in snapshot.values())):
        raise ApiError("400 Bad Request", "invalid_snapshot")


def encoded(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode()


def reply(status, data=b"", revision=None, content_type="application/json"):
    headers = [("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff")]
    if status not in {"204 No Content", "304 Not Modified"}:
        headers.extend([("Content-Type", content_type), ("Content-Length", str(len(data)))])
    if revision is not None:
        headers.append(("ETag", f'"{revision}"'))
    return status, headers, data


class SyncApp:
    def __init__(self, database, signup_code="", trust_proxy=False):
        self.database = database
        self.signup_code = signup_code
        self.trust_proxy = trust_proxy
        with closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript(SCHEMA)

    def connect(self):
        db = sqlite3.connect(self.database, isolation_level=None, timeout=8)
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def __call__(self, environ, start_response):
        try:
            result = self.dispatch(environ)
        except ApiError as error:
            result = reply(error.status, encoded({"error": error.code}))
        except Exception:
            logging.exception("Sync request failed")
            result = reply("503 Service Unavailable", encoded({"error": "unavailable"}))
        status, headers, data = result
        start_response(status, headers)
        return [data]

    def dispatch(self, environ):
        method, route = environ["REQUEST_METHOD"], environ["PATH_INFO"]
        if method == "GET" and route == "/healthz":
            with closing(self.connect()) as db:
                db.execute("SELECT 1 FROM accounts LIMIT 1")
            return reply("200 OK", encoded({"ok": True}))
        if method == "POST" and route in ("/v1/register", "/v1/login"):
            return self.authenticate(environ, register=route.endswith("/register"))
        if (method, route) not in {
            ("DELETE", "/v1/session"), ("GET", "/v1/snapshot"), ("PUT", "/v1/snapshot")
        }:
            raise ApiError("404 Not Found", "not_found")
        with closing(self.connect()) as db:
            account, session = self.account_for(db, environ)
            if method == "DELETE":
                db.execute("DELETE FROM sessions WHERE token_hash=?", (session,))
                return reply("204 No Content")
            if method == "GET":
                revision = self.revision(db, account)
                if environ.get("HTTP_IF_NONE_MATCH") == f'"{revision}"':
                    return reply("304 Not Modified", revision=revision)
                row = db.execute(
                    "SELECT revision,data FROM snapshots WHERE account_id=?", (account,)
                ).fetchone()
                if row is None:
                    return reply("204 No Content", revision=0)
                return reply("200 OK", row[1], row[0], "application/octet-stream")
            return self.put_snapshot(db, account, environ)

    def rate_limit(self, db, environ, email, now, register):
        peer = environ.get("REMOTE_ADDR", "")
        if self.trust_proxy:
            peer = environ.get("HTTP_X_FORWARDED_FOR", peer).split(",")[0].strip()
        window = now // 900
        buckets = [(f"ip:{peer}", 36), (f"pair:{peer}:{email}", 10)]
        if register:
            buckets.append((f"signup:{peer}", 8))
        db.execute("BEGIN IMMEDIATE")
        with db:
            db.execute("DELETE FROM auth_limits WHERE window<?", (window - 1,))
            for key, limit in buckets:
                db.execute("""
                    INSERT INTO auth_limits VALUES (?, ?, 1)
                    ON CONFLICT(bucket,window) DO UPDATE SET attempts=attempts+1
                """, (key, window))
                count = db.execute(
                    "SELECT attempts FROM auth_limits WHERE bucket=? AND window=?",
                    (key, window),
                ).fetchone()[0]
                if count > limit:
                    raise ApiError("429 Too Many Requests", "try_later")

    def authenticate(self, environ, register):
        data = json_object(body(environ, 4096))
        email, password = data.get("email"), data.get("password")
        if not isinstance(email, str) or not isinstance(password, str):
            raise ApiError("400 Bad Request", "invalid_credentials")
        email = email.strip().lower()
        try:
            password_bytes = password.encode()
        except UnicodeError as error:
            raise ApiError("400 Bad Request", "invalid_credentials") from error
        if (len(email) > 254 or not EMAIL.fullmatch(email)
                or len(password) < 12 or len(password_bytes) > 512):
            raise ApiError("400 Bad Request", "invalid_credentials")
        now = int(time.time())
        with closing(self.connect()) as db:
            self.rate_limit(db, environ, email, now, register)
            if register:
                code = data.get("code", "")
                if self.signup_code and (not isinstance(code, str) or not hmac.compare_digest(
                    self.signup_code.encode(), code.encode("utf-8", errors="replace")
                )):
                    raise ApiError("403 Forbidden", "signup_code_required")
                account = secrets.token_hex(16)
                salt = secrets.token_bytes(16)
                digest = password_hash(password, salt)
            else:
                row = db.execute(
                    "SELECT id,salt,password_hash FROM accounts WHERE email=?", (email,)
                ).fetchone()
                account, salt, digest = row or (None, bytes(16), bytes(32))
                if not hmac.compare_digest(password_hash(password, salt), digest) or account is None:
                    raise ApiError("401 Unauthorized", "invalid_credentials")
            token = secrets.token_urlsafe(32)
            db.execute("BEGIN IMMEDIATE")
            with db:
                if register:
                    try:
                        db.execute("INSERT INTO accounts VALUES (?,?,?,?)",
                                   (account, email, salt, digest))
                    except sqlite3.IntegrityError as error:
                        raise ApiError("409 Conflict", "account_exists") from error
                db.execute("DELETE FROM sessions WHERE expires_at<=?", (now,))
                db.execute("INSERT INTO sessions VALUES (?,?,?)",
                           (token_hash(token), account, now + SESSION_SECONDS))
        return reply("201 Created" if register else "200 OK",
                     encoded({"id": account, "email": email, "token": token}))

    @staticmethod
    def account_for(db, environ):
        authorization = TOKEN.fullmatch(environ.get("HTTP_AUTHORIZATION", ""))
        if authorization:
            session = token_hash(authorization[1])
            row = db.execute(
                "SELECT account_id FROM sessions WHERE token_hash=? AND expires_at>?",
                (session, int(time.time())),
            ).fetchone()
            if row:
                return row[0], session
        raise ApiError("401 Unauthorized", "session_expired")

    @staticmethod
    def revision(db, account):
        row = db.execute("SELECT revision FROM snapshots WHERE account_id=?", (account,)).fetchone()
        return row[0] if row else 0

    def put_snapshot(self, db, account, environ):
        expected = REVISION.fullmatch(environ.get("HTTP_IF_MATCH", ""))
        request_id = environ.get("HTTP_X_UPLOAD_ID", "")
        if not expected or not HEX_ID.fullmatch(request_id):
            raise ApiError("400 Bad Request", "invalid_revision")
        raw = body(environ, MAX_SNAPSHOT)
        checked_snapshot(raw)
        digest = hashlib.sha256(raw).digest()
        db.execute("BEGIN IMMEDIATE")
        with db:
            # Recheck after a large upload in case the session was revoked mid-request.
            self.account_for(db, environ)
            previous = db.execute("""
                SELECT revision,digest FROM uploads WHERE account_id=? AND request_id=?
            """, (account, request_id)).fetchone()
            if previous:
                if not hmac.compare_digest(previous[1], digest):
                    raise ApiError("422 Unprocessable Entity", "upload_id_reused")
                return reply("204 No Content", revision=previous[0])
            revision = self.revision(db, account)
            if revision != int(expected[1]):
                raise ApiError("409 Conflict", "revision_changed")
            revision += 1
            db.execute("""
                INSERT INTO snapshots VALUES (?,?,?)
                ON CONFLICT(account_id) DO UPDATE SET revision=excluded.revision,data=excluded.data
            """, (account, revision, raw))
            db.execute("INSERT INTO uploads VALUES (?,?,?,?)", (account, request_id, revision, digest))
        return reply("204 No Content", revision=revision)


def create_app():
    database = Path(os.environ.get("SYNC_DATABASE", "data/sync.sqlite3"))
    database.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    return SyncApp(database, os.environ.get("SYNC_SIGNUP_CODE", ""),
                   os.environ.get("SYNC_TRUST_PROXY") == "1")


if __name__ == "__main__":
    from wsgiref.simple_server import make_server

    port = int(os.environ.get("SYNC_DEV_PORT", "8080"))
    with make_server("127.0.0.1", port, create_app()) as server:
        print(f"READY {server.server_port}", flush=True)
        server.serve_forever()
