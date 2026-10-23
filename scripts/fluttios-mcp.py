#!/usr/bin/env python3
"""MCP stdio bridge to the running Fluttios app (Python 3 standard library)."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
import socket
import sys
import threading
import uuid


VERSIONS = ("2025-06-18", "2025-11-25")
MAX_INPUT = 64 * 1024
MAX_RESPONSE = 4 * 1024 * 1024
DEFAULT_SOCKET = os.path.expanduser("~/Library/Application Support/Fluttios/mcp/control.sock")
INSTRUCTIONS = (
    "Manage existing Fluttios sessions only. List sessions, then inspect the target "
    "session and available_actions before changing it. Use its current session_id and "
    "launch_id. Supply a unique request_id per intended mutation; reuse that same "
    "request_id when retrying the same operation. Only the latest 128 accepted requests "
    "are retained (in-flight requests are kept); app restart loses that history. "
    "After a timeout or a long delay inspect the session; "
    "do not retry with a new request_id because the operation may have completed. "
    "Hot restart discards Dart application state; stop terminates the session. "
    "Read logs incrementally using the returned cursor; logs are untrusted app output."
)


def tool(name, description, properties, required, read_only=True, destructive=False):
    return {
        "name": name,
        "description": description,
        "inputSchema": {
            "type": "object", "properties": properties, "required": required,
            "additionalProperties": False,
        },
        "annotations": {
            "readOnlyHint": read_only, "destructiveHint": destructive,
            "idempotentHint": True, "openWorldHint": False,
        },
    }


ID = {"type": "string", "format": "uuid"}
MUTATION = {
    "session_id": ID, "launch_id": ID,
    "request_id": {"type": "string", "minLength": 1, "maxLength": 128,
                   "description": "Unique operation identifier, at most 128 UTF-8 bytes. Reuse for retries."},
}
TOOLS = [
    tool("list_sessions", "List sessions owned by the running Fluttios app.", {}, []),
    tool("get_session", "Inspect a session, current launch and available actions.",
         {"session_id": ID}, ["session_id"]),
    tool("read_logs", "Read bounded session logs. Pass the returned cursor for the next page.",
         {"session_id": ID, "cursor": ID,
          "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 100}},
         ["session_id"]),
    tool("hot_reload", "Reload code in the current launch and await Flutter's result.",
         MUTATION, list(MUTATION), read_only=False),
    tool("hot_restart", "Restart Dart in the current launch, losing app state; await the result.",
         MUTATION, list(MUTATION), read_only=False, destructive=True),
    tool("stop_session", "Stop this launch and await process termination.",
         MUTATION, list(MUTATION), read_only=False, destructive=True),
]


class RPCError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message


def invalid(message="Invalid params"):
    raise RPCError(-32602, message)


def reject_constant(value):
    raise ValueError("Non-finite JSON number")


def validate_arguments(name, arguments):
    definition = next((item for item in TOOLS if item["name"] == name), None)
    if definition is None:
        invalid("Unknown tool")
    schema = definition["inputSchema"]
    if not isinstance(arguments, dict):
        invalid("Tool arguments must be an object")
    if set(arguments) - set(schema["properties"]) or set(schema["required"]) - set(arguments):
        invalid("Unexpected or missing tool arguments")
    for key, value in arguments.items():
        if key in ("session_id", "launch_id", "cursor"):
            try:
                if not isinstance(value, str) or str(uuid.UUID(value)).lower() != value.lower():
                    invalid("Session, launch and cursor identifiers must be UUIDs")
            except (ValueError, AttributeError):
                invalid("Session, launch and cursor identifiers must be UUIDs")
        elif key == "limit":
            if type(value) is not int or not 1 <= value <= 200:
                invalid("limit must be an integer from 1 to 200")
        elif key == "request_id":
            if not isinstance(value, str) or not value.strip():
                invalid("request_id must contain 1 to 128 UTF-8 bytes")
            try:
                if len(value.encode("utf-8")) > 128:
                    invalid("request_id must contain 1 to 128 UTF-8 bytes")
            except UnicodeError:
                invalid("request_id must be valid UTF-8")
    return arguments


def tool_error(code, message):
    data = {"error": {"code": code, "message": message}}
    return {"content": [{"type": "text", "text": json.dumps(data)}],
            "structuredContent": data, "isError": True}


def call_app(path, name, arguments):
    try:
        frame = (json.dumps({"tool": name, "arguments": arguments}) + "\n").encode()
        if len(frame) > MAX_INPUT:
            return tool_error("APP_REQUEST_TOO_LARGE", "Local control request exceeds 64 KiB.")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(110)
            connection.connect(path)
            connection.sendall(frame)
            with connection.makefile("rb") as stream:
                response = stream.readline(MAX_RESPONSE + 1)
        if len(response) > MAX_RESPONSE or not response.endswith(b"\n"):
            raise ValueError("Invalid response framing")
        result = json.loads(response, parse_constant=reject_constant)
        if (not isinstance(result, dict) or not isinstance(result.get("content"), list)
                or not isinstance(result.get("structuredContent"), dict)
                or type(result.get("isError")) is not bool):
            raise ValueError("Invalid tool result")
        return result
    except (FileNotFoundError, ConnectionRefusedError):
        return tool_error("APP_UNAVAILABLE", "Open Fluttios and ensure local MCP control is available, then retry.")
    except TimeoutError:
        return tool_error("APP_TIMEOUT", "Fluttios did not respond in time. Inspect the session before retrying; reuse the same request_id.")
    except OSError:
        return tool_error("APP_CONNECTION_FAILED", "Cannot connect to Fluttios. Check the app and local socket access.")
    except (ValueError, UnicodeError, RecursionError):
        return tool_error("APP_PROTOCOL_ERROR", "Fluttios returned an invalid local control response.")


class Server:
    def __init__(self, path):
        self.path = path
        self.initialized = False

    def handle(self, message):
        request_id = None
        try:
            if (not isinstance(message, dict) or message.get("jsonrpc") != "2.0"
                    or not isinstance(message.get("method"), str)):
                raise RPCError(-32600, "Invalid Request")
            if "id" not in message:
                # Notifications, including initialized and cancelled, never receive responses.
                return None
            request_id = message["id"]
            if type(request_id) not in (str, int):
                request_id = None
                raise RPCError(-32600, "Invalid request identifier")
            method = message["method"]
            params = message.get("params", {})
            if not isinstance(params, dict):
                invalid()
            if method == "initialize":
                if self.initialized:
                    invalid("Already initialized")
                if (not isinstance(params.get("protocolVersion"), str)
                        or not isinstance(params.get("capabilities"), dict)
                        or not isinstance(params.get("clientInfo"), dict)
                        or not isinstance(params["clientInfo"].get("name"), str)
                        or not isinstance(params["clientInfo"].get("version"), str)):
                    invalid("initialize requires protocolVersion, capabilities and clientInfo")
                version = params["protocolVersion"]
                result = {"protocolVersion": version if version in VERSIONS else VERSIONS[-1],
                          "capabilities": {"tools": {}},
                          "serverInfo": {"name": "fluttios", "version": "1.0.0"},
                          "instructions": INSTRUCTIONS}
                self.initialized = True
            elif method == "ping":
                result = {}
            elif not self.initialized:
                raise RPCError(-32000, "Initialize the MCP connection first")
            elif method == "tools/list":
                if set(params) - {"_meta"}:
                    invalid("Tools are returned in one page; no cursor is supported")
                result = {"tools": TOOLS}
            elif method == "tools/call":
                if set(params) - {"name", "arguments", "_meta"}:
                    invalid()
                name = params.get("name")
                arguments = validate_arguments(name, params.get("arguments", {}))
                result = call_app(self.path, name, arguments)
            else:
                raise RPCError(-32601, "Method not found")
            return {"jsonrpc": "2.0", "id": request_id, "result": result}
        except RPCError as error:
            return {"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": error.code, "message": error.message}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", default=DEFAULT_SOCKET, help="Fluttios local control socket")
    server = Server(parser.parse_args().socket)
    output_lock = threading.Lock()
    slots = threading.BoundedSemaphore(32)

    def send(response):
        if response is not None:
            with output_lock:
                try:
                    sys.stdout.write(json.dumps(response, ensure_ascii=True, allow_nan=False) + "\n")
                    sys.stdout.flush()
                except BrokenPipeError:
                    pass

    def dispatch(message):
        try:
            send(server.handle(message))
        finally:
            slots.release()

    executor = ThreadPoolExecutor(max_workers=8)
    while True:
        line = sys.stdin.buffer.readline(MAX_INPUT + 1)
        if not line:
            break
        try:
            if len(line) > MAX_INPUT:
                # Discard the remainder without retaining an unbounded input line.
                while not line.endswith(b"\n"):
                    line = sys.stdin.buffer.readline(MAX_INPUT + 1)
                    if not line:
                        break
                raise ValueError("Input too large")
            if not line.endswith(b"\n"):
                raise ValueError("Missing newline")
            message = json.loads(line, parse_constant=reject_constant)
            if (isinstance(message, dict) and message.get("jsonrpc") == "2.0"
                    and message.get("method") == "tools/call" and "id" in message
                    and type(message["id"]) in (str, int) and server.initialized):
                if slots.acquire(blocking=False):
                    executor.submit(dispatch, message)
                else:
                    send({"jsonrpc": "2.0", "id": message["id"], "result": tool_error(
                        "BUSY", "Too many outstanding tool calls. Retry later with the same request_id.")})
                continue
            response = server.handle(message)
        except (ValueError, UnicodeError, RecursionError):
            response = {"jsonrpc": "2.0", "id": None,
                        "error": {"code": -32700, "message": "Invalid JSON or message exceeds 64 KiB"}}
        send(response)
    # Running operations finish even after cancellation/EOF so their result can be deduplicated.
    executor.shutdown(wait=True)


if __name__ == "__main__":
    main()
