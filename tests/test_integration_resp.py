#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

import io
import pytest
import sys
import os
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))

from nexus_client import NexusClient, NexusClientError


class MockRespServer:
    """In-memory RESP simulation server for high-speed offline verification."""

    def __init__(self):
        self.strings = {}
        self.hashes = {}
        self.lists = {}
        self.sets = {}

    def handle(self, req_bytes: bytes) -> bytes:
        rfile = io.BytesIO(req_bytes)
        first_line = rfile.readline()
        if not first_line.startswith(b"*"):
            return b"-ERR invalid command format\r\n"

        count = int(first_line[1:-2])
        args = []
        for _ in range(count):
            len_line = rfile.readline()
            length = int(len_line[1:-2])
            payload = rfile.read(length)
            rfile.read(2)  # skip CRLF
            args.append(payload.decode("utf-8"))

        cmd = args[0].upper()

        if cmd == "PING":
            if len(args) > 1:
                arg_bytes = args[1].encode("utf-8")
                return f"${len(arg_bytes)}\r\n{args[1]}\r\n".encode("utf-8")
            return b"+PONG\r\n"

        elif cmd == "SET":
            self.strings[args[1]] = args[2]
            return b"+OK\r\n"

        elif cmd == "GET":
            val = self.strings.get(args[1])
            if val is None:
                return b"$-1\r\n"
            vb = val.encode("utf-8")
            return f"${len(vb)}\r\n{val}\r\n".encode("utf-8")

        elif cmd == "DEL":
            deleted = 0
            for k in args[1:]:
                if k in self.strings:
                    del self.strings[k]
                    deleted += 1
            return f":{deleted}\r\n".encode("utf-8")

        elif cmd == "EXISTS":
            found = sum(1 for k in args[1:] if k in self.strings)
            return f":{found}\r\n".encode("utf-8")

        elif cmd == "INCR":
            curr = int(self.strings.get(args[1], "0"))
            curr += 1
            self.strings[args[1]] = str(curr)
            return f":{curr}\r\n".encode("utf-8")

        elif cmd == "HSET":
            key, field, val = args[1], args[2], args[3]
            if key not in self.hashes:
                self.hashes[key] = {}
            is_new = 1 if field not in self.hashes[key] else 0
            self.hashes[key][field] = val
            return f":{is_new}\r\n".encode("utf-8")

        elif cmd == "HGET":
            val = self.hashes.get(args[1], {}).get(args[2])
            if val is None:
                return b"$-1\r\n"
            vb = val.encode("utf-8")
            return f"${len(vb)}\r\n{val}\r\n".encode("utf-8")

        elif cmd == "LPUSH":
            key = args[1]
            if key not in self.lists:
                self.lists[key] = []
            for v in args[2:]:
                self.lists[key].insert(0, v)
            return f":{len(self.lists[key])}\r\n".encode("utf-8")

        elif cmd == "LPOP":
            key = args[1]
            lst = self.lists.get(key, [])
            if not lst:
                return b"$-1\r\n"
            popped = lst.pop(0)
            pb = popped.encode("utf-8")
            return f"${len(pb)}\r\n{popped}\r\n".encode("utf-8")

        elif cmd == "SADD":
            key = args[1]
            if key not in self.sets:
                self.sets[key] = set()
            added = 0
            for m in args[2:]:
                if m not in self.sets[key]:
                    self.sets[key].add(m)
                    added += 1
            return f":{added}\r\n".encode("utf-8")

        elif cmd == "SISMEMBER":
            key, member = args[1], args[2]
            is_mem = 1 if member in self.sets.get(key, set()) else 0
            return f":{is_mem}\r\n".encode("utf-8")

        return b"-ERR unknown command\r\n"


def test_mock_resp_server_full_matrix():
    """Verify end-to-end client command generation and simulated execution."""
    server = MockRespServer()

    # Wire mock client to execute via server.handle
    client = NexusClient()
    def mock_exec(*args):
        buf = bytearray()
        buf.extend(f"*{len(args)}\r\n".encode("utf-8"))
        for arg in args:
            s_bytes = str(arg).encode("utf-8")
            buf.extend(f"${len(s_bytes)}\r\n".encode("utf-8"))
            buf.extend(s_bytes)
            buf.extend(b"\r\n")
        resp_bytes = server.handle(bytes(buf))
        client._rfile = io.BytesIO(resp_bytes)
        return client._read_response()

    client._execute_command = mock_exec

    # Test PING
    assert client.ping() == "PONG"
    assert client.ping("hello") == "hello"

    # Test String operations
    assert client.set("cluster:config:active", "true") is True
    assert client.get("cluster:config:active") == "true"
    assert client.exists("cluster:config:active") == 1
    assert client.delete("cluster:config:active") == 1
    assert client.get("cluster:config:active") is None

    # Test INCR
    assert client.incr("counter") == 1
    assert client.incr("counter") == 2

    # Test Hash operations
    assert client.hset("user:101", "name", "Alice") == 1
    assert client.hget("user:101", "name") == "Alice"
    assert client.hset("user:101", "name", "Alicia") == 0

    # Test List operations
    assert client.lpush("jobs", "job1", "job2") == 2
    assert client.lpop("jobs") == "job2"
    assert client.lpop("jobs") == "job1"
    assert client.lpop("jobs") is None

    # Test Set operations
    assert client.sadd("group", "m1", "m2", "m1") == 2
    assert client.sismember("group", "m1") is True
    assert client.sismember("group", "m3") is False
