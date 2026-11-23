import json
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

from sync_server import SyncApp
import test_sync_server as sync_tests


class SocialTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.database = Path(cls.tmp.name) / 'social.sqlite3'
        cls.app = SyncApp(cls.database)
        cls.accounts = []
        for i in range(3):
            status, _, raw = cls.request('POST', '/v1/register', json.dumps({
                'email': f'social-{i}@example.test', 'password': 'eight888',
            }).encode())
            assert status == 201, raw
            cls.accounts.append(json.loads(raw))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def request(cls, method, route, body=b'', **headers):
        return sync_tests.SyncServerTest.request.__func__(cls, method, route, body, **headers)

    def setUp(self):
        with closing(sqlite3.connect(self.database, isolation_level=None)) as db:
            for table in ['messages', 'friend_requests', 'friendships', 'social_limits']:
                db.execute('DELETE FROM ' + table)
        self.a, self.b, self.c = self.accounts
        self.pa, self.pb, self.pc = [self.call(a, 'GET', '/v1/profile')[1] for a in self.accounts]

    def call(self, account, method, route, value=None, query=''):
        status, _, raw = self.request(method, route,
            json.dumps(value).encode() if value is not None else b'',
            HTTP_AUTHORIZATION='Bearer ' + account['token'], QUERY_STRING=query)
        return status, json.loads(raw)

    def befriend(self):
        self.assertEqual(self.call(self.a, 'POST', '/v1/friends', {'id': self.pb['id']})[0], 200)
        self.assertEqual(self.call(self.b, 'POST', '/v1/friend-requests', {'id': self.pa['id']})[0], 200)

    def test_eight_character_password_and_seven_rejection(self):
        status, _, _ = self.request('POST', '/v1/login', json.dumps({
            'email': self.a['email'], 'password': 'eight888',
        }).encode())
        self.assertEqual(status, 200)
        status, _, _ = self.request('POST', '/v1/register', json.dumps({
            'email': 'short@example.test', 'password': 'seven77',
        }).encode())
        self.assertEqual(status, 400)

    def test_profile_is_stable_editable_and_never_exposes_login_details(self):
        edited = {'nickname': '小屿', 'avatar': 'fox', 'bio': '慢慢成长', 'title': '星夜旅人'}
        status, value = self.call(self.a, 'PUT', '/v1/profile', edited)
        self.assertEqual(status, 200)
        self.assertEqual(value, {**edited, 'id': self.pa['id']})
        self.assertNotEqual(self.pa['id'], self.a['id'])
        self.assertEqual(self.call(self.b, 'GET', '/v1/people', query='id=' + self.pa['id'])[1], value)
        self.assertFalse({'email', 'token', 'account_id'} & value.keys())
        self.assertEqual(self.call(self.a, 'PUT', '/v1/profile', {**edited, 'id': self.pb['id']})[0], 400)
        self.assertEqual(self.call(self.b, 'GET', '/v1/profile')[1]['id'], self.pb['id'])
        self.assertEqual(self.call(self.a, 'PUT', '/v1/profile', {**edited, 'avatar': '<script>'})[0], 400)

    def test_friend_acceptance_requires_recipient_and_is_idempotent(self):
        self.call(self.a, 'POST', '/v1/friends', {'id': self.pb['id']})
        self.call(self.a, 'POST', '/v1/friends', {'id': self.pb['id']})
        self.assertEqual(len(self.call(self.b, 'GET', '/v1/friend-requests')[1]['incoming']), 1)
        self.assertEqual(self.call(self.a, 'POST', '/v1/friend-requests', {'id': self.pb['id']})[0], 404)
        self.assertEqual(self.call(self.c, 'POST', '/v1/friend-requests', {'id': self.pa['id']})[0], 404)
        self.assertEqual(self.call(self.a, 'POST', '/v1/friends', {'id': self.pa['id']})[0], 400)
        self.befriend()
        self.assertEqual(self.call(self.b, 'POST', '/v1/friend-requests', {'id': self.pa['id']})[0], 200)
        self.assertEqual(len(self.call(self.a, 'GET', '/v1/friends')[1]['friends']), 1)
        self.assertEqual(self.call(self.b, 'GET', '/v1/friends')[1]['friends'][0]['id'], self.pa['id'])

    def test_reject_cancel_and_remove(self):
        self.call(self.a, 'POST', '/v1/friends', {'id': self.pb['id']})
        self.call(self.b, 'DELETE', '/v1/friend-requests', {'id': self.pa['id']})
        self.assertEqual(self.call(self.a, 'GET', '/v1/friend-requests')[1]['outgoing'], [])
        self.befriend()
        self.call(self.b, 'DELETE', '/v1/friends', {'id': self.pa['id']})
        self.assertEqual(self.call(self.a, 'GET', '/v1/friends')[1]['friends'], [])
        self.assertEqual(self.call(self.a, 'GET', '/v1/messages', query='id=' + self.pb['id'])[0], 403)

    def test_message_privacy_retry_and_concurrent_duplicate(self):
        payload = {'id': self.pb['id'], 'clientId': 'a' * 32, 'text': '你好，小屿！'}
        self.assertEqual(self.call(self.a, 'POST', '/v1/messages', payload)[0], 403)
        self.befriend()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.call(self.a, 'POST', '/v1/messages', payload), range(2)))
        self.assertEqual(sorted(r[0] for r in results), [200, 201])
        self.assertEqual(results[0][1]['id'], results[1][1]['id'])
        self.assertEqual(self.call(self.a, 'POST', '/v1/messages', {**payload, 'text': 'different'})[0], 409)
        incoming = self.call(self.b, 'GET', '/v1/messages', query='id=' + self.pa['id'])[1]['messages']
        self.assertEqual(len(incoming), 1)
        self.assertFalse(incoming[0]['mine'])
        self.assertEqual(incoming[0]['text'], payload['text'])
        self.assertEqual(self.call(self.c, 'GET', '/v1/messages', query='id=' + self.pa['id'])[0], 403)
        self.assertEqual(self.call(self.a, 'POST', '/v1/messages', {**payload, 'clientId': 'b' * 32, 'text': ' '})[0], 400)

    def test_history_pagination_is_ordered_and_bounded(self):
        self.befriend()
        with closing(sqlite3.connect(self.database, isolation_level=None)) as db:
            for i in range(55):
                db.execute('INSERT INTO messages(sender,recipient,client_id,text,created_at) VALUES (?,?,?,?,?)',
                           (self.a['id'], self.b['id'], f'{i:032x}', str(i), i))
        latest = self.call(self.b, 'GET', '/v1/messages', query='id=' + self.pa['id'])[1]
        self.assertEqual([m['text'] for m in latest['messages']], [str(i) for i in range(5, 55)])
        self.assertTrue(latest['hasMore'])
        older = self.call(self.b, 'GET', '/v1/messages', query=f"id={self.pa['id']}&before={latest['messages'][0]['id']}")[1]
        self.assertEqual([m['text'] for m in older['messages']], [str(i) for i in range(5)])
        self.assertFalse(older['hasMore'])
        self.assertEqual(self.call(self.a, 'GET', '/v1/messages', query='id=' + self.pb['id'] + '&before=-1')[0], 400)

    def test_existing_database_and_sessions_survive_schema_addition(self):
        self.befriend()
        SyncApp(self.database)
        self.assertEqual(self.call(self.a, 'GET', '/v1/profile')[1]['id'], self.pa['id'])
        self.assertEqual(len(self.call(self.a, 'GET', '/v1/friends')[1]['friends']), 1)
        for route in ['/v1/profile', '/v1/friends', '/v1/messages']:
            self.assertEqual(self.request('GET', route)[0], 401)


if __name__ == '__main__':
    unittest.main()
