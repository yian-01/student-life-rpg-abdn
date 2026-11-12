import hashlib
import io
import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from wsgiref.util import setup_testing_defaults

from sync_server import SyncApp


class SyncServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.database = Path(cls.tmp.name) / "sync.sqlite3"
        cls.app = SyncApp(cls.database, signup_code="invite")
        cls.alice = cls.register("alice@example.test")
        cls.bob = cls.register("bob@example.test")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def request(cls, method, path, body=b"", **headers):
        env = {}
        setup_testing_defaults(env)
        env.update(
            REQUEST_METHOD=method, PATH_INFO=path, CONTENT_LENGTH=str(len(body)),
            **{"wsgi.input": io.BytesIO(body)}, **headers
        )
        result = []
        data = b"".join(cls.app(env, lambda status, headers: result.extend((status, headers))))
        return int(result[0].split()[0]), dict(result[1]), data

    @classmethod
    def register(cls, email):
        status, _, data = cls.request(
            "POST", "/v1/register",
            json.dumps({"email": email, "password": "a long test password", "code": "invite"}).encode(),
        )
        assert status == 201, data
        return json.loads(data)

    @staticmethod
    def snapshot(value):
        return json.dumps({
            "format": "student-life-backup", "version": 1,
            "payload": value, "sha256": hashlib.sha256(value.encode()).hexdigest(),
        }).encode()

    @classmethod
    def read(cls, account, **headers):
        return cls.request("GET", "/v1/snapshot",
                           HTTP_AUTHORIZATION="Bearer " + account["token"], **headers)

    @classmethod
    def put(cls, account, revision, operation, data):
        return cls.request(
            "PUT", "/v1/snapshot", data, HTTP_AUTHORIZATION="Bearer " + account["token"],
            HTTP_IF_MATCH=f'"{revision}"', HTTP_X_UPLOAD_ID=operation,
        )

    def test_account_isolation_conflict_and_idempotent_upload(self):
        alice = self.alice
        bob = self.bob
        first = self.snapshot("first")
        second = self.snapshot("second")
        self.assertEqual(self.read(alice)[0], 204)
        self.assertEqual(self.read(bob)[0], 204)
        self.assertEqual(self.put(alice, 0, "a" * 32, first)[1]["ETag"], '"1"')
        self.assertEqual(self.put(alice, 0, "b" * 32, second)[0], 409)
        self.assertEqual(self.read(alice, HTTP_IF_NONE_MATCH='"1"')[0], 304)
        self.assertEqual(self.put(alice, 1, "b" * 32, second)[1]["ETag"], '"2"')
        self.assertEqual(self.put(alice, 0, "a" * 32, first)[1]["ETag"], '"1"')
        self.assertEqual(self.put(alice, 0, "a" * 32, second)[0], 422)
        self.assertEqual(self.read(alice)[2], second)
        self.assertEqual(self.read(bob)[0], 204)

    def test_concurrent_updates_cannot_overwrite_same_revision(self):
        account = self.register("concurrent@example.test")
        barrier = Barrier(2)

        def put(key):
            barrier.wait(timeout=5)
            return self.put(account, 0, key * 32, self.snapshot(key))[0]

        with ThreadPoolExecutor(max_workers=2) as executor:
            self.assertEqual(sorted(executor.map(put, ["c", "d"])), [204, 409])
        self.assertEqual(self.read(account)[1]["ETag"], '"1"')

    def test_invalid_snapshot_and_authentication(self):
        self.assertEqual(self.request("GET", "/v1/snapshot")[0], 401)
        self.assertEqual(self.put(self.bob, 0, "e" * 32, b'{}')[0], 400)
        self.assertEqual(self.read(self.bob)[0], 204)
        wrong = json.dumps({"email": self.alice["email"], "password": "incorrect password"}).encode()
        self.assertEqual(self.request("POST", "/v1/login", wrong)[0], 401)
        wrong_invite = json.dumps({"email": "new@example.test", "password": "password long"}).encode()
        self.assertEqual(self.request("POST", "/v1/register", wrong_invite)[0], 403)

    def test_login_and_revoke_one_device(self):
        status, _, data = self.request(
            "POST", "/v1/login",
            json.dumps({"email": self.bob["email"].upper(), "password": "a long test password"}).encode(),
        )
        self.assertEqual(status, 200)
        second = json.loads(data)
        self.assertEqual(second["id"], self.bob["id"])
        status, _, _ = self.request(
            "DELETE", "/v1/session", HTTP_AUTHORIZATION="Bearer " + second["token"],
        )
        self.assertEqual(status, 204)
        self.assertEqual(self.read(second)[0], 401)
        self.assertEqual(self.read(self.bob)[0], 204)
