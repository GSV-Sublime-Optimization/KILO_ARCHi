import contextlib
import http.client
import io
import json
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid
from pathlib import Path

from marketplace.model import MAX_BODY, json_bytes
from marketplace.server import LocalServer
from marketplace.store import Store
from marketplace.tests.fixtures import PASSWORD, draft


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-marketplace-http-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "synthetic.sqlite3"
        self.store = Store(self.path)
        self.server = LocalServer(self.store, 0)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.assertFalse(self.thread.is_alive())

    def request(self, method, path, body=None, token=None, headers=None, raw=None):
        values = dict(headers or {})
        if token is not None:
            values["Authorization"] = "Bearer " + token
        if body is not None:
            values.setdefault("Content-Type", "application/json")
            raw = json_bytes(body)
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=raw, headers=values)
            response = conn.getresponse()
            data = response.read()
            return response.status, dict(response.getheaders()), json.loads(data) if data else None
        finally:
            conn.close()

    def account(self, handle="synthetic_user"):
        status, _, _ = self.request("POST", "/v1/accounts", {"handle": handle, "displayName": "Synthetic User", "password": PASSWORD})
        self.assertEqual(status, 201)
        status, _, data = self.request("POST", "/v1/sessions", {"handle": handle, "password": PASSWORD})
        self.assertEqual(status, 201)
        return data["token"]

    def raw_request(self, message):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.sendall(message)
            sock.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        header, body = b"".join(chunks).split(b"\r\n\r\n", 1)
        return int(header.split(b" ")[1]), json.loads(body)

    def test_loopback_health_and_security_headers(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, headers, data = self.request("GET", "/v1/health")
        self.assertEqual(status, 200)
        self.assertEqual(data, {"service": "archi-marketplace", "apiVersion": 1, "mode": "development",
                               "commerce": False, "recipeSchema": "archi-item-design/v1", "maximumRecipeBytes": 4096})
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(headers["Connection"], "close")
        self.assertNotIn("Access-Control-Allow-Origin", headers)
        uuid.UUID(headers["X-Request-ID"])

    def test_loopback_bind_does_not_use_reverse_dns(self):
        probe = Store(self.path.with_name("dns-free.sqlite3"), clock=lambda: self.now)
        with patch("socket.getfqdn", side_effect=AssertionError("loopback bind must not resolve DNS")):
            server = LocalServer(probe, 0)
        try:
            self.assertEqual(server.server_name, "127.0.0.1")
            self.assertGreater(server.server_port, 0)
        finally:
            server.server_close()

    def test_active_port_cannot_be_shared_by_another_service(self):
        with self.assertRaises(OSError):
            LocalServer(self.store, self.port)
        self.assertEqual(self.request("GET", "/v1/health")[0], 200)

    def test_host_origin_and_absolute_url_rejected(self):
        for headers, code in (({"Host": "attacker.invalid"}, "host_forbidden"),
                              ({"Host": "127.0.0.1:1"}, "host_forbidden"),
                              ({"Origin": "https://attacker.invalid"}, "origin_forbidden"),
                              ({"Origin": "null"}, "origin_forbidden"),
                              ({"Origin": f"http://127.0.0.1:{self.port}"}, "origin_forbidden")):
            with self.subTest(headers=headers):
                status, _, data = self.request("GET", "/v1/health", headers=headers)
                self.assertEqual((status, data["error"]["code"]), (403, code))
        status, _, _ = self.request("GET", f"http://127.0.0.1:{self.port}/v1/health")
        self.assertEqual(status, 400)

    def test_repeated_headers_and_unsupported_transfer_encoding_fail_closed(self):
        host = f"Host: 127.0.0.1:{self.port}\r\n".encode()
        for extra in (host, b"Content-Length: 0\r\nContent-Length: 1\r\n", b"Transfer-Encoding: chunked\r\n",
                      b"Content-Encoding: gzip\r\n", b"Authorization: Bearer one\r\nAuthorization: Bearer two\r\n"):
            with self.subTest(extra=extra):
                status, _ = self.raw_request(b"POST /v1/accounts HTTP/1.1\r\n" + host + extra + b"\r\n")
                self.assertEqual(status, 400)

    def test_oversized_or_incomplete_body_is_not_accepted(self):
        status, _, data = self.request("POST", "/v1/accounts", headers={"Content-Length": str(MAX_BODY + 1), "Content-Type": "application/json"})
        self.assertEqual((status, data["error"]["code"]), (413, "body_too_large"))
        status, _ = self.raw_request(f"POST /v1/accounts HTTP/1.0\r\nHost: 127.0.0.1:{self.port}\r\nContent-Length: 100\r\nContent-Type: application/json\r\n\r\n{{".encode())
        self.assertEqual(status, 400)
        with contextlib.closing(sqlite3.connect(self.path)) as db, db:
            self.assertEqual(db.execute("SELECT count(*) FROM accounts").fetchone()[0], 0)

    def test_content_type_duplicate_json_and_unsupported_method(self):
        for raw, headers, expected in ((b"{}", {}, 415), (b"{}", {"Content-Type": "text/plain"}, 415),
                                       (b'{"handle":1,"handle":2}', {"Content-Type": "application/json"}, 400)):
            status, _, _ = self.request("POST", "/v1/accounts", raw=raw, headers=headers)
            self.assertEqual(status, expected)
        status, _, data = self.request("PATCH", "/v1/health")
        self.assertEqual((status, data["error"]["code"]), (405, "method_not_allowed"))

    def test_auth_missing_invalid_and_revoked_are_actionable(self):
        status, _, data = self.request("GET", "/v1/me")
        self.assertEqual((status, data["error"]["code"]), (401, "unauthorized"))
        self.assertEqual(self.request("GET", "/v1/me", token="x" * 43)[0], 401)
        token = self.account()
        self.assertEqual(self.request("GET", "/v1/me", token=token)[0], 200)
        self.assertEqual(self.request("DELETE", "/v1/sessions/current", token=token)[2], {"signedOut": True})
        self.assertEqual(self.request("GET", "/v1/me", token=token)[0], 401)

    def test_live_creator_to_collector_flow_and_exact_download(self):
        creator = self.account("synthetic_creator")
        collector = self.account("synthetic_collector")
        status, _, data = self.request("POST", "/v1/listings", draft(), token=creator,
                                       headers={"Idempotency-Key": str(uuid.uuid4())})
        self.assertEqual(status, 201)
        listing = data["listing"]
        self.assertEqual(self.request("GET", "/v1/catalog")[2]["total"], 0)
        self.assertEqual(self.request("POST", f'/v1/listings/{listing["id"]}/publish', {"expectedVersion": 1}, token=collector)[0], 404)
        status, _, data = self.request("POST", f'/v1/listings/{listing["id"]}/publish', {"expectedVersion": 1}, token=creator)
        self.assertEqual(status, 200)
        published = data["listing"]
        self.assertEqual(self.request("GET", "/v1/catalog?q=Synthetic")[2]["items"], [published])
        status, _, acquired = self.request("POST", "/v1/inventory", {"listingID": listing["id"], "version": 2,
                                          "recipeID": published["recipeID"]}, token=collector)
        self.assertEqual(status, 201)
        self.assertEqual(self.request("GET", "/v1/inventory", token=collector)[2]["items"], [acquired["entry"]])
        status, headers, recipe = self.request("GET", f'/v1/listings/{listing["id"]}/versions/2/package', token=collector)
        self.assertEqual((status, recipe), (200, published["recipe"]))
        self.assertEqual(headers["X-ARCHi-Recipe-ID"], published["recipeID"])
        self.assertIn("attachment;", headers["Content-Disposition"])
        self.assertLessEqual(int(headers["Content-Length"]), 4096)

    def test_disconnect_after_submission_retries_without_duplicate_creation(self):
        token = self.account()
        key = str(uuid.uuid4())
        headers = {"Content-Type": "application/json", "Authorization": "Bearer " + token, "Idempotency-Key": key}
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.request("POST", "/v1/listings", body=json_bytes(draft()), headers=headers)
        # Intentionally never consume the response; transport cancellation is not rollback.
        conn.close()
        status, _, retry = self.request("POST", "/v1/listings", draft(), token=token, headers={"Idempotency-Key": key})
        self.assertEqual(status, 201)
        listing = retry["listing"]
        items = self.request("GET", "/v1/me/listings", token=token)[2]
        self.assertEqual(items["total"], 1)
        self.assertEqual(items["items"], [listing])

    def test_bad_queries_and_secret_bearing_query_auth_are_rejected(self):
        for suffix in ("?limit=1&limit=2", "?q=%FF", "?limit=1&offset=0&q=x&extra=x&other=x", "?token=secret"):
            with self.subTest(suffix=suffix):
                self.assertEqual(self.request("GET", "/v1/catalog" + suffix)[0], 400)
        self.assertEqual(self.request("GET", "/v1/me?token=secret")[0], 400)

    def test_auth_rate_limit_bounds_password_work_without_echoing_input(self):
        for _ in range(20):
            self.assertEqual(self.request("POST", "/v1/sessions", {"handle": "bad", "password": "short"})[0], 422)
        status, headers, data = self.request("POST", "/v1/sessions", {"handle": "bad", "password": "short"})
        self.assertEqual((status, data["error"]["code"]), (429, "rate_limited"))
        self.assertEqual(headers["Retry-After"], "60")
        self.assertNotIn("short", json.dumps(data))
        self.assertEqual(self.request("GET", "/v1/health")[0], 200)

    def test_no_request_or_secret_logging_or_payment_endpoints(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            token = self.account()
            self.request("GET", "/v1/catalog?q=private_search")
            for route in ("/v1/payments", "/v1/balance", "/v1/checkout"):
                self.assertEqual(self.request("POST", route, {}, token=token)[0], 404)
        self.assertEqual(output.getvalue(), "")
        with contextlib.closing(sqlite3.connect(self.path)) as db, db:
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertFalse({"payments", "balances", "orders"} & tables)

    def test_storage_failure_returns_service_error_without_database_details(self):
        token = self.account()
        with contextlib.closing(sqlite3.connect(self.path)) as db, db:
            db.execute("ALTER TABLE inventory RENAME TO missing_inventory")
        status, _, data = self.request("GET", "/v1/inventory", token=token)
        self.assertEqual((status, data["error"]["code"]), (503, "storage_unavailable"))
        self.assertNotIn(str(self.path), json.dumps(data))
        self.assertNotIn("missing_inventory", json.dumps(data))


class ProcessLifecycleTests(unittest.TestCase):
    def test_cli_restart_and_shutdown_preserve_synthetic_state_without_logs(self):
        with tempfile.TemporaryDirectory(prefix="archi-marketplace-process-") as folder:
            database = Path(folder) / "synthetic.sqlite3"
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            command = [sys.executable, "-m", "marketplace", "--database", str(database), "--port", str(port)]

            def run_process():
                process = subprocess.Popen(
                    command,
                    cwd=Path(__file__).resolve().parents[2],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0),
                )
                deadline = time.monotonic() + 30
                last_probe = "no response"
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        stdout, stderr = process.communicate(timeout=5)
                        self.fail(
                            f"Synthetic CLI server exited during startup (rc={process.returncode}); "
                            f"stdout={stdout!r}; stderr={stderr!r}"
                        )
                    try:
                        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=0.3)
                        conn.request("GET", "/v1/health")
                        response = conn.getresponse()
                        body = response.read()
                        conn.close()
                        last_probe = f"HTTP {response.status} body={body[:240]!r}"
                        if response.status == 200:
                            return process
                    except OSError as exc:
                        last_probe = f"{type(exc).__name__}: {exc}"
                        time.sleep(0.05)
                stdout, stderr = stop_process(process)
                self.fail(
                    "Synthetic CLI server did not become healthy; "
                    f"last_probe={last_probe}; stdout={stdout!r}; stderr={stderr!r}"
                )

            def stop_process(process):
                if sys.platform == "win32":
                    process.send_signal(signal.CTRL_BREAK_EVENT)
                else:
                    process.terminate()
                return process.communicate(timeout=5)

            def request(method, path, body=None, token=None):
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                headers = {"Content-Type": "application/json"}
                if token:
                    headers["Authorization"] = "Bearer " + token
                conn.request(method, path, body=json_bytes(body) if body else None, headers=headers)
                response = conn.getresponse()
                value = json.loads(response.read())
                conn.close()
                return response.status, value

            process = run_process()
            try:
                account_body = {"handle": "synthetic_restart", "displayName": "Synthetic Restart", "password": PASSWORD}
                self.assertEqual(request("POST", "/v1/accounts", account_body)[0], 201)
                session = request("POST", "/v1/sessions", {"handle": "synthetic_restart", "password": PASSWORD})[1]
                token = session["token"]
                listing = request("POST", "/v1/listings", draft(), token)[1]["listing"]
            finally:
                stdout, stderr = stop_process(process)
            self.assertEqual(process.returncode, 0)
            self.assertNotIn(PASSWORD, stdout + stderr)
            self.assertNotIn(token, stdout + stderr)
            self.assertEqual(stderr, "")
            process = run_process()
            try:
                self.assertEqual(request("GET", "/v1/me", token=token)[1]["account"], session["account"])
                self.assertEqual(request("GET", "/v1/me/listings", token=token)[1]["items"], [listing])
            finally:
                stdout, stderr = stop_process(process)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(stderr, "")


if __name__ == "__main__":
    unittest.main()
