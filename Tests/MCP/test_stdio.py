"""Black-box protocol checks; the fake controls transport, never session semantics."""
import json
from contextlib import contextmanager
from pathlib import Path
import socket
import selectors
import subprocess
import sys
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "fluttios-mcp.py"
SESSION = "22c5ecba-fbc8-4a0a-9c1e-cc69b136bf58"
LAUNCH = "3a9fa3d9-efda-42ae-ac2d-de94b9b3a401"
INITIALIZE = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-11-25", "capabilities": {},
    "clientInfo": {"name": "test", "version": "1"}}}


def request(identifier, method, params=None):
    return {"jsonrpc": "2.0", "id": identifier, "method": method, "params": params or {}}


@contextmanager
def backend(count, respond):
    """Real framing with caller-controlled replies/scheduling, no session rules."""
    with tempfile.TemporaryDirectory(prefix="fluttios-", dir="/tmp") as directory:
        path = str(Path(directory) / "control.sock")
        received, failures, workers = [], [], []
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(path)
            listener.listen()
            listener.settimeout(5)

            def handle(connection):
                try:
                    with connection, connection.makefile("rb") as stream:
                        message = json.loads(stream.readline())
                        received.append(message)
                        connection.sendall(respond(message))
                except Exception as error:
                    failures.append(error)

            def serve():
                try:
                    for _ in range(count):
                        connection, _ = listener.accept()
                        worker = threading.Thread(target=handle, args=(connection,))
                        workers.append(worker)
                        worker.start()
                except Exception as error:
                    failures.append(error)

            worker = threading.Thread(target=serve)
            worker.start()
            try:
                yield path, received
            finally:
                worker.join(timeout=6)
                for client in workers:
                    client.join(timeout=6)
                if worker.is_alive() or any(client.is_alive() for client in workers):
                    raise AssertionError("Backend fixture did not finish")
                if failures:
                    raise AssertionError(failures)


OK = b'{"content":[{"type":"text","text":"{}"}],"structuredContent":{},"isError":false}\n'


class StdioTests(unittest.TestCase):
    def run_bridge(self, messages, socket_path, prefix=b""):
        payload = prefix + b"".join((json.dumps(item) + "\n").encode() for item in messages)
        # Files avoid pipe-capacity deadlocks when replaying all requests at once.
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as output:
            source.write(payload)
            source.seek(0)
            result = subprocess.run([sys.executable, str(SCRIPT), "--socket", str(socket_path)],
                                    stdin=source, stdout=output, stderr=subprocess.PIPE, timeout=8)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(result.stderr, b"")
            output.seek(0)
            return sorted([json.loads(line) for line in output], key=lambda item: item["id"] or -1)

    def test_handshake_notifications_and_strict_arguments(self):
        # Prevent a wrong launch or bool-as-int from reaching a mutation/backend.
        invalid_arguments = [
            ("get_session", {"session_id": "not-a-uuid"}),
            ("get_session", {"session_id": SESSION, "unknown": True}),
            ("read_logs", {"session_id": SESSION, "limit": True}),
            ("read_logs", {"session_id": SESSION, "limit": 201}),
            ("read_logs", {"session_id": SESSION, "cursor": 0}),
            ("hot_reload", {"session_id": SESSION, "request_id": "op"}),
            ("hot_restart", {"session_id": SESSION, "launch_id": LAUNCH, "request_id": " "}),
            ("stop_session", {"session_id": SESSION, "launch_id": LAUNCH, "request_id": "x" * 129}),
            ("stop_session", {"session_id": SESSION, "launch_id": LAUNCH, "request_id": "я" * 65}),
            ("list_sessions", {"session_id": SESSION}),
            ("unknown", {}),
        ]
        messages = [INITIALIZE, {"jsonrpc": "2.0", "method": "notifications/initialized"},
                    {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 9}},
                    request(2, "ping"), request(3, "tools/list")]
        messages += [request(index, "tools/call", {"name": name, "arguments": arguments})
                     for index, (name, arguments) in enumerate(invalid_arguments, 4)]
        messages += [request(15, "unknown")]
        responses = self.run_bridge(messages, "/does-not-exist")
        self.assertEqual(len(responses), 15)
        self.assertEqual(responses[0]["result"]["protocolVersion"], "2025-11-25")
        self.assertEqual(responses[1], {"jsonrpc": "2.0", "id": 2, "result": {}})
        tools = responses[2]["result"]["tools"]
        self.assertEqual([item["name"] for item in tools],
                         ["list_sessions", "get_session", "read_logs", "hot_reload", "hot_restart", "stop_session",
                          "list_projects", "list_devices", "start_session", "rerun_session", "open_deep_link", "take_screenshot"])
        self.assertTrue(next(item for item in tools if item["name"] == "stop_session")["annotations"]["destructiveHint"])
        self.assertEqual([item["error"]["code"] for item in responses[3:]], [-32602] * 11 + [-32601])

    def test_new_tools_preserve_explicit_targets_and_native_image_content(self):
        mutation = {"session_id": SESSION, "launch_id": LAUNCH, "request_id": "new-op"}
        operations = [
            ("list_projects", {}), ("list_devices", {"project_id": SESSION}),
            ("start_session", {"project_id": SESSION, "device_id": "emulator-5554", "request_id": "start"}),
            ("rerun_session", mutation),
            ("open_deep_link", {**mutation, "url": "myapp://profile?a=1&b=2"}),
            ("take_screenshot", mutation),
        ]
        image = {"type": "image", "mimeType": "image/jpeg", "data": "aW1hZ2U="}
        reply = json.dumps({"content": [image], "structuredContent": {}, "isError": False}).encode() + b"\n"
        with backend(len(operations), lambda _: reply) as (path, received):
            responses = self.run_bridge([INITIALIZE] + [
                request(index, "tools/call", {"name": name, "arguments": arguments})
                for index, (name, arguments) in enumerate(operations, 2)], path)
        self.assertCountEqual(received, [{"tool": name, "arguments": arguments} for name, arguments in operations])
        self.assertTrue(all(response["result"]["content"] == [image] for response in responses[1:]))

    def test_new_tool_invalid_targets_never_reach_backend(self):
        mutation = {"session_id": SESSION, "launch_id": LAUNCH, "request_id": "operation"}
        operations = [
            ("list_devices", {"project_id": "invalid"}),
            ("start_session", {"project_id": SESSION, "device_id": "", "request_id": "start"}),
            ("start_session", {"project_id": SESSION, "device_id": "D\n2", "request_id": "start"}),
            ("start_session", {"project_id": SESSION, "device_id": "\ud800", "request_id": "start"}),
            ("rerun_session", {"session_id": SESSION, "request_id": "op"}),
            ("open_deep_link", {**mutation, "url": 123}),
            ("open_deep_link", {**mutation, "url": "x" * 8193}),
            ("take_screenshot", {**mutation, "path": "/tmp/private"}),
        ]
        responses = self.run_bridge([INITIALIZE] + [
            request(index, "tools/call", {"name": name, "arguments": arguments})
            for index, (name, arguments) in enumerate(operations, 2)], "/not-a-socket")
        self.assertEqual([response["error"]["code"] for response in responses[1:]], [-32602] * len(operations))

    def test_framing_recovery_and_unavailable_app_do_not_echo_input(self):
        # Oversized/malformed inputs cannot desynchronize later requests or leak paths.
        secret = "private-token-do-not-echo"
        malformed = (b"{invalid " + secret.encode() + b"}\n" + b"x" * 65537 + b"\n")
        responses = self.run_bridge([
            INITIALIZE, request(2, "tools/call", {"name": "list_sessions"})],
            "/missing/" + secret, prefix=malformed)
        self.assertEqual([item["error"]["code"] for item in responses[:2]], [-32700, -32700])
        error = responses[-1]["result"]
        self.assertTrue(error["isError"])
        self.assertEqual(error["structuredContent"]["error"]["code"], "APP_UNAVAILABLE")
        self.assertNotIn(secret, json.dumps(responses))

    def test_socket_receives_explicit_target_and_bad_backend_framing_is_reported(self):
        # One real UNIX socket fixture covers wire routing and a truncated reply.
        def respond(message):
            return OK if message["tool"] == "hot_reload" else b'{"private":"must-not-echo"}'

        with backend(2, respond) as (path, received):
            arguments = {"session_id": SESSION, "launch_id": LAUNCH, "request_id": "operation-1"}
            responses = self.run_bridge([
                INITIALIZE,
                request(2, "tools/call", {"name": "hot_reload", "arguments": arguments}),
                request(3, "tools/call", {"name": "get_session", "arguments": {"session_id": SESSION}})], path)
            self.assertIn({"tool": "hot_reload", "arguments": arguments}, received)
            self.assertFalse(responses[1]["result"]["isError"])
            self.assertEqual(responses[2]["result"]["structuredContent"]["error"]["code"], "APP_PROTOCOL_ERROR")
            self.assertNotIn("must-not-echo", json.dumps(responses))

    def test_slow_mutation_does_not_block_state_queries_or_ping(self):
        # Fourth test owns concurrency: a blocked Flutter call must not freeze inspection.
        entered, release = threading.Event(), threading.Event()

        def respond(message):
            if message["tool"] == "hot_reload":
                entered.set()
                if not release.wait(5):
                    raise AssertionError("Mutation was never released")
            return OK

        with backend(2, respond) as (path, _):
            process = subprocess.Popen([sys.executable, str(SCRIPT), "--socket", path],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       bufsize=0)
            def send(message):
                process.stdin.write((json.dumps(message) + "\n").encode())
                process.stdin.flush()

            def read():
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=3), "MCP response blocked by mutation")
                return json.loads(process.stdout.readline())

            try:
                send(INITIALIZE)
                self.assertEqual(read()["id"], 1)
                send(request(2, "tools/call", {"name": "hot_reload", "arguments": {
                    "session_id": SESSION, "launch_id": LAUNCH, "request_id": "slow"}}))
                self.assertTrue(entered.wait(3))
                send(request(3, "tools/call", {"name": "get_session", "arguments": {"session_id": SESSION}}))
                send(request(4, "ping"))
                self.assertEqual({read()["id"], read()["id"]}, {3, 4})
                release.set()
                self.assertEqual(read()["id"], 2)
                process.stdin.close()
                self.assertEqual(process.wait(timeout=3), 0)
                self.assertEqual(process.stderr.read(), b"")
            finally:
                release.set()
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stdout.close()
                process.stderr.close()
                if not process.stdin.closed:
                    process.stdin.close()


if __name__ == "__main__":
    unittest.main()
