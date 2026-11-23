"""Account-scoped profiles, mutual friendships and private text messages."""
import secrets
import sqlite3
import time
from urllib.parse import parse_qs

SOCIAL_METHODS = {
    '/v1/profile': {'GET', 'PUT'},
    '/v1/people': {'GET'},
    '/v1/friends': {'GET', 'POST', 'DELETE'},
    '/v1/friend-requests': {'GET', 'POST', 'DELETE'},
    '/v1/messages': {'GET', 'POST'},
}
SOCIAL_SCHEMA = """
CREATE TABLE IF NOT EXISTS profiles (
 account_id TEXT PRIMARY KEY REFERENCES accounts(id), public_id TEXT UNIQUE NOT NULL,
 nickname TEXT NOT NULL, avatar TEXT NOT NULL, bio TEXT NOT NULL, title TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS friend_requests (
 sender TEXT NOT NULL REFERENCES accounts(id), recipient TEXT NOT NULL REFERENCES accounts(id),
 created_at INTEGER NOT NULL, PRIMARY KEY(sender,recipient), CHECK(sender<>recipient)
);
CREATE TABLE IF NOT EXISTS friendships (
 first TEXT NOT NULL REFERENCES accounts(id), second TEXT NOT NULL REFERENCES accounts(id),
 PRIMARY KEY(first,second), CHECK(first<second)
);
CREATE TABLE IF NOT EXISTS messages (
 id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL REFERENCES accounts(id),
 recipient TEXT NOT NULL REFERENCES accounts(id), client_id TEXT NOT NULL,
 text TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(sender,client_id), CHECK(sender<>recipient)
);
CREATE INDEX IF NOT EXISTS messages_pair ON messages(sender,recipient,id);
CREATE INDEX IF NOT EXISTS requests_recipient ON friend_requests(recipient,created_at);
CREATE TABLE IF NOT EXISTS social_limits (
 account_id TEXT NOT NULL REFERENCES accounts(id), kind TEXT NOT NULL, window INTEGER NOT NULL,
 attempts INTEGER NOT NULL, PRIMARY KEY(account_id,kind,window)
);
"""


class SocialError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def fail(status, code):
    raise SocialError(status, code)


def profile(db, account):
    row = db.execute('SELECT public_id,nickname,avatar,bio,title FROM profiles WHERE account_id=?', (account,)).fetchone()
    if row is None:
        for _ in range(10):
            try:
                db.execute('INSERT INTO profiles VALUES (?,?,?,?,?,?)',
                           (account, secrets.token_hex(5).upper(), '新同学', 'cat', '', '课屿居民'))
                break
            except sqlite3.IntegrityError:
                if db.execute('SELECT 1 FROM profiles WHERE account_id=?', (account,)).fetchone():
                    break
        row = db.execute('SELECT public_id,nickname,avatar,bio,title FROM profiles WHERE account_id=?', (account,)).fetchone()
    if row is None:
        fail('503 Service Unavailable', 'unavailable')
    return dict(zip(['id', 'nickname', 'avatar', 'bio', 'title'], row))


def text(value, minimum, maximum):
    if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum or any(ord(c) < 32 and c != '\n' for c in value):
        fail('400 Bad Request', 'invalid_social_input')
    return value.strip()


def budget(db, account, kind, limit):
    window = int(time.time()) // 60
    db.execute('DELETE FROM social_limits WHERE window<?', (window - 15,))
    db.execute('INSERT INTO social_limits VALUES (?,?,?,1) ON CONFLICT(account_id,kind,window) DO UPDATE SET attempts=attempts+1',
               (account, kind, window))
    count = db.execute('SELECT attempts FROM social_limits WHERE account_id=? AND kind=? AND window=?', (account, kind, window)).fetchone()[0]
    if count > limit:
        fail('429 Too Many Requests', 'try_later')


def handle_social(db, account, method, route, environ, read_body):
    query = parse_qs(environ.get('QUERY_STRING', ''), keep_blank_values=True)
    data = read_body() if method != 'GET' else {}
    # Serialize decisions with writes: accepting/removing friendship and sending
    # cannot race and authorize messages after a friendship was removed.
    db.execute('BEGIN IMMEDIATE')
    with db:
        own = profile(db, account)
        budget(db, account, 'read' if method == 'GET' else 'write', 180 if method == 'GET' else 40)
        if route == '/v1/profile':
            if method == 'PUT':
                if set(data) != {'nickname', 'avatar', 'bio', 'title'}:
                    fail('400 Bad Request', 'invalid_social_input')
                nickname = text(data.get('nickname'), 1, 24)
                bio, title = text(data.get('bio'), 0, 200), text(data.get('title'), 0, 20)
                avatar = data.get('avatar')
                if avatar not in ('cat', 'fox', 'rabbit', 'leaf', 'star'):
                    fail('400 Bad Request', 'invalid_social_input')
                db.execute('UPDATE profiles SET nickname=?,avatar=?,bio=?,title=? WHERE account_id=?',
                           (nickname, avatar, bio, title, account))
            return '200 OK', profile(db, account)
        if route == '/v1/friends' and method == 'GET':
            ids = db.execute('SELECT CASE WHEN first=? THEN second ELSE first END FROM friendships WHERE first=? OR second=?',
                             (account, account, account)).fetchall()
            return '200 OK', {'friends': [profile(db, r[0]) for r in ids]}
        if route == '/v1/friend-requests' and method == 'GET':
            rows = db.execute('SELECT sender,recipient FROM friend_requests WHERE sender=? OR recipient=? ORDER BY created_at DESC', (account, account)).fetchall()
            return '200 OK', {'incoming': [profile(db, a) for a, b in rows if b == account],
                              'outgoing': [profile(db, b) for a, b in rows if a == account]}
        public_id = query.get('id', [''])[0] if method == 'GET' else data.get('id')
        if not isinstance(public_id, str) or len(public_id.strip()) != 10:
            fail('400 Bad Request', 'invalid_social_input')
        row = db.execute('SELECT account_id FROM profiles WHERE public_id=?', (public_id.strip().upper(),)).fetchone()
        if row is None:
            fail('404 Not Found', 'person_not_found')
        peer = row[0]
        if route == '/v1/people':
            return '200 OK', profile(db, peer)
        if peer == account:
            fail('400 Bad Request', 'cannot_add_self')
        pair = tuple(sorted((account, peer)))
        friends = db.execute('SELECT 1 FROM friendships WHERE first=? AND second=?', pair).fetchone() is not None
        if route == '/v1/friends':
            if method == 'POST':
                if not friends:
                    budget(db, account, 'friend_request', 10)
                    db.execute('INSERT OR IGNORE INTO friend_requests VALUES (?,?,?)', (account, peer, int(time.time())))
            else:
                db.execute('DELETE FROM friendships WHERE first=? AND second=?', pair)
                db.execute('DELETE FROM friend_requests WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)', (account, peer, peer, account))
            return '200 OK', {'ok': True}
        if route == '/v1/friend-requests':
            if method == 'POST':
                pending = db.execute('SELECT 1 FROM friend_requests WHERE sender=? AND recipient=?', (peer, account)).fetchone()
                if not pending and not friends:
                    fail('404 Not Found', 'request_not_found')
                db.execute('INSERT OR IGNORE INTO friendships VALUES (?,?)', pair)
                db.execute('DELETE FROM friend_requests WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)', (peer, account, account, peer))
            else:
                # Recipient can reject; sender can cancel. Cannot affect other users.
                db.execute('DELETE FROM friend_requests WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)', (peer, account, account, peer))
            return '200 OK', {'ok': True}
        if not friends:
            fail('403 Forbidden', 'friends_only')
        if method == 'POST':
            client_id = data.get('clientId')
            if not isinstance(client_id, str) or len(client_id) != 32 or any(c not in '0123456789abcdef' for c in client_id):
                fail('400 Bad Request', 'invalid_social_input')
            content = text(data.get('text'), 1, 2000)
            previous = db.execute('SELECT id,recipient,text FROM messages WHERE sender=? AND client_id=?', (account, client_id)).fetchone()
            if previous:
                if previous[1:] != (peer, content):
                    fail('409 Conflict', 'message_id_reused')
                return '200 OK', {'id': previous[0]}
            budget(db, account, 'message', 30)
            cursor = db.execute('INSERT INTO messages(sender,recipient,client_id,text,created_at) VALUES (?,?,?,?,?)',
                                (account, peer, client_id, content, int(time.time())))
            return '201 Created', {'id': cursor.lastrowid}
        try:
            before = int(query.get('before', ['9223372036854775807'])[0])
            if not 0 < before <= 9223372036854775807:
                raise ValueError
        except ValueError:
            fail('400 Bad Request', 'invalid_social_input')
        rows = db.execute('SELECT id,sender,text,created_at FROM messages WHERE ((sender=? AND recipient=?) OR (sender=? AND recipient=?)) AND id<? ORDER BY id DESC LIMIT 51',
                          (account, peer, peer, account, before)).fetchall()
        return '200 OK', {'messages': [{'id': r[0], 'mine': r[1] == account, 'text': r[2], 'createdAt': r[3]} for r in reversed(rows[:50])],
                          'hasMore': len(rows) > 50}
