#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

import socket
from typing import Any, Dict, List, Optional, Union


class NexusClientError(Exception):
    """Base exception for Nexus client operations."""
    pass


class NexusClient:
    """
    High-performance, production-grade Python client for Nexus IMDG clusters.
    Communicates via native Redis RESP3 wire protocol over TCP.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 6379, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock: Optional[socket.socket] = None
        self._rfile = None

    def connect(self) -> "NexusClient":
        """Establish TCP connection to target Nexus cluster node."""
        if self._sock is not None:
            return self

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.connect((self.host, self.port))
        self._sock = s
        self._rfile = s.makefile("rb")
        return self

    def is_connected(self) -> bool:
        """Check if socket connection is alive."""
        return self._sock is not None

    def close(self) -> None:
        """Gracefully terminate client socket connection."""
        if self._rfile is not None:
            try:
                self._rfile.close()
            except Exception:
                pass
            self._rfile = None

        if self._sock is not None:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None

    def __enter__(self) -> "NexusClient":
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.close()

    def ping(self, message: Optional[str] = None) -> str:
        """Send PING command and return PONG or echoed payload."""
        cmd = ["PING"] if message is None else ["PING", message]
        return self._execute_command(*cmd)

    def get(self, key: str) -> Optional[str]:
        """Retrieve cached string value by key."""
        return self._execute_command("GET", key)

    def set(self, key: str, value: str, ex: Optional[int] = None, px: Optional[int] = None) -> bool:
        """Store key-value entry with optional TTL in seconds (ex) or milliseconds (px)."""
        args = ["SET", key, str(value)]
        if ex is not None:
            args.extend(["EX", str(ex)])
        elif px is not None:
            args.extend(["PX", str(px)])

        res = self._execute_command(*args)
        return res == "OK"

    def setnx(self, key: str, value: str) -> bool:
        """Set key if not already existing. Returns True if key was set."""
        res = self._execute_command("SETNX", key, str(value))
        return res == 1

    def mget(self, *keys: str) -> List[Optional[str]]:
        """Retrieve multiple string values in a single roundtrip."""
        if not keys:
            return []
        return self._execute_command("MGET", *keys)

    def mset(self, mapping: Dict[str, str]) -> bool:
        """Set multiple key-value pairs atomically."""
        if not mapping:
            return True
        args = ["MSET"]
        for k, v in mapping.items():
            args.extend([k, str(v)])
        res = self._execute_command(*args)
        return res == "OK"

    def delete(self, *keys: str) -> int:
        """Delete one or more keys. Returns number of keys removed."""
        if not keys:
            return 0
        return self._execute_command("DEL", *keys)

    def exists(self, *keys: str) -> int:
        """Check if one or more keys exist in keyspace."""
        if not keys:
            return 0
        return self._execute_command("EXISTS", *keys)

    def expire(self, key: str, seconds: int) -> bool:
        """Set a time-to-live expiration deadline on key in seconds."""
        res = self._execute_command("EXPIRE", key, str(seconds))
        return res == 1

    def ttl(self, key: str) -> int:
        """Get remaining time to live in seconds (-2 not found, -1 no ttl)."""
        return self._execute_command("TTL", key)

    def incr(self, key: str, delta: int = 1) -> int:
        """Atomically increment integer value of key by delta."""
        if delta == 1:
            return self._execute_command("INCR", key)
        return self._execute_command("INCRBY", key, str(delta))

    def decr(self, key: str, delta: int = 1) -> int:
        """Atomically decrement integer value of key by delta."""
        if delta == 1:
            return self._execute_command("DECR", key)
        return self._execute_command("DECRBY", key, str(delta))

    # --- Hash Commands ---
    def hset(self, key: str, field: str, value: str) -> int:
        """Set field in hash at key. Returns 1 if field is new, 0 if updated."""
        return self._execute_command("HSET", key, field, str(value))

    def hget(self, key: str, field: str) -> Optional[str]:
        """Retrieve value of field in hash at key."""
        return self._execute_command("HGET", key, field)

    def hdel(self, key: str, field: str) -> int:
        """Delete field in hash. Returns 1 if removed, 0 if absent."""
        return self._execute_command("HDEL", key, field)

    def hgetall(self, key: str) -> Dict[str, str]:
        """Retrieve all fields and values of hash at key."""
        raw = self._execute_command("HGETALL", key)
        if not raw:
            return {}
        result = {}
        for i in range(0, len(raw), 2):
            result[raw[i]] = raw[i + 1]
        return result

    # --- List Commands ---
    def lpush(self, key: str, *values: str) -> int:
        """Prepend one or more elements to list at key."""
        return self._execute_command("LPUSH", key, *[str(v) for v in values])

    def rpush(self, key: str, *values: str) -> int:
        """Append one or more elements to list at key."""
        return self._execute_command("RPUSH", key, *[str(v) for v in values])

    def lpop(self, key: str) -> Optional[str]:
        """Remove and return first element of list."""
        return self._execute_command("LPOP", key)

    def rpop(self, key: str) -> Optional[str]:
        """Remove and return last element of list."""
        return self._execute_command("RPOP", key)

    def llen(self, key: str) -> int:
        """Return length of list at key."""
        return self._execute_command("LLEN", key)

    # --- Set Commands ---
    def sadd(self, key: str, *members: str) -> int:
        """Add one or more members to set at key."""
        return self._execute_command("SADD", key, *[str(m) for m in members])

    def smembers(self, key: str) -> List[str]:
        """Return all members of set at key."""
        return self._execute_command("SMEMBERS", key) or []

    def sismember(self, key: str, member: str) -> bool:
        """Check if member belongs to set at key."""
        res = self._execute_command("SISMEMBER", key, str(member))
        return res == 1

    # --- Server Information ---
    def info(self) -> str:
        """Return formatted server statistics string."""
        return self._execute_command("INFO")

    def dbsize(self) -> int:
        """Return number of keys stored in current database."""
        return self._execute_command("DBSIZE")

    def flushdb(self) -> bool:
        """Purge all entries from the active partition store."""
        return self._execute_command("FLUSHDB") == "OK"

    # --- Protocol Core ---
    def _execute_command(self, *args: str) -> Any:
        if not self.is_connected():
            self.connect()

        # Format RESP command: *<count>\r\n$<len>\r\n<arg>\r\n...
        buf = bytearray()
        buf.extend(f"*{len(args)}\r\n".encode("utf-8"))
        for arg in args:
            s_bytes = str(arg).encode("utf-8")
            buf.extend(f"${len(s_bytes)}\r\n".encode("utf-8"))
            buf.extend(s_bytes)
            buf.extend(b"\r\n")

        self._sock.sendall(buf)
        return self._read_response()

    def _read_response(self) -> Any:
        line = self._rfile.readline()
        if not line:
            raise NexusClientError("Server closed connection prematurely")

        prefix = line[0:1]
        payload = line[1:-2].decode("utf-8")

        if prefix == b"+":
            return payload
        elif prefix == b"-":
            raise NexusClientError(payload)
        elif prefix == b":":
            return int(payload)
        elif prefix == b"$":
            length = int(payload)
            if length == -1:
                return None
            data = self._rfile.read(length)
            crlf = self._rfile.read(2)
            if crlf != b"\r\n":
                raise NexusClientError("Malformed bulk string termination")
            return data.decode("utf-8")
        elif prefix == b"*":
            count = int(payload)
            if count == -1:
                return None
            return [self._read_response() for _ in range(count)]
        elif prefix == b"#":
            return payload == "t"
        elif prefix == b",":
            return float(payload)
        elif prefix == b"_":
            return None
        else:
            raise NexusClientError(f"Unknown RESP prefix byte: {prefix!r}")
