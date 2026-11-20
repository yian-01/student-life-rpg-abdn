import hashlib
import io
import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from wsgiref.util import setup_testing_defaults

from sync_server import SyncApp, web_origin


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
        payload = json.dumps({
            "createdAt": "2026-11-12T00:00:00Z", "campus": "{}", "tasks": value,
        })
        return json.dumps({
            "format": "student-life-backup", "version": 1,
            "payload": payload, "sha256": hashlib.sha256(payload.encode()).hexdigest(),
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

class CorsServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.app = SyncApp(Path(cls.tmp.name) / "cors.sqlite3", signup_code="invite",
                          trust_proxy=True, allowed_origins=["https://app.example.test"])
        cls.account = SyncServerTest.register.__func__(cls, "cors@example.test")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def request(cls, method, path, body=b"", **headers):
        return SyncServerTest.request.__func__(cls, method, path, body, **headers)

    def test_cross_origin_preflight_accepts_sync_protocol_without_cookies(self):
        status, headers, data = self.request(
            "OPTIONS", "/v1/snapshot", HTTP_ORIGIN="https://app.example.test",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="PUT",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="Authorization, Content-Type, If-Match, X-Upload-Id",
        )
        self.assertEqual(status, 204)
        self.assertEqual(data, b"")
        self.assertEqual(headers["Access-Control-Allow-Origin"], "https://app.example.test")
        self.assertIn("PUT", headers["Access-Control-Allow-Methods"])
        self.assertIn("x-upload-id", headers["Access-Control-Allow-Headers"])
        self.assertNotIn("Access-Control-Allow-Credentials", headers)

    def test_bad_sources_methods_and_headers_are_rejected(self):
        for origin, method, headers in [
            ("https://untrusted.example.test", "PUT", "authorization"),
            ("null", "PUT", "authorization"),
            ("https://app.example.test", "PATCH", "authorization"),
            ("https://app.example.test", "PUT", "x-unapproved"),
        ]:
            with self.subTest(origin=origin, method=method, headers=headers):
                status, _, _ = self.request(
                    "OPTIONS", "/v1/snapshot", HTTP_ORIGIN=origin,
                    HTTP_ACCESS_CONTROL_REQUEST_METHOD=method,
                    HTTP_ACCESS_CONTROL_REQUEST_HEADERS=headers,
                )
                self.assertEqual(status, 403)
        status, headers, _ = self.request("POST", "/v1/login", HTTP_ORIGIN="https://untrusted.example.test")
        self.assertEqual(status, 403)
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_allowed_origin_still_requires_bearer_and_exposes_errors_and_etag(self):
        status, headers, _ = self.request("GET", "/v1/snapshot", HTTP_ORIGIN="https://app.example.test")
        self.assertEqual(status, 401)
        self.assertEqual(headers["Access-Control-Allow-Origin"], "https://app.example.test")
        status, headers, _ = self.request(
            "GET", "/v1/snapshot", HTTP_ORIGIN="https://app.example.test",
            HTTP_AUTHORIZATION="Bearer " + self.account["token"],
        )
        self.assertEqual(status, 204)
        self.assertEqual(headers["ETag"], '"0"')
        self.assertIn("ETag", headers["Access-Control-Expose-Headers"])
        self.assertEqual(headers["Vary"], "Origin")
        self.assertEqual(self.request("GET", "/v1/snapshot")[0], 401)

    def test_same_origin_behind_trusted_https_proxy_needs_no_allowlist(self):
        status, headers, _ = self.request(
            "GET", "/v1/snapshot", HTTP_ORIGIN="https://api.example.test",
            HTTP_HOST="api.example.test", HTTP_X_FORWARDED_PROTO="https",
            HTTP_AUTHORIZATION="Bearer " + self.account["token"],
        )
        self.assertEqual(status, 204)
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_origin_configuration_is_explicit_and_canonical(self):
        self.assertEqual(web_origin("https://APP.example.test:443/"), "https://app.example.test")
        for invalid in ["*", "https://*.example.test", "https://user:secret@app.example.test",
                        "https://app.example.test/path", "http://public.example.test", "null"]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                web_origin(invalid)
