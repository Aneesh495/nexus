#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

import io
import pytest
import sys
import os

# Add python directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "python"))

from nexus_client import NexusClient, NexusClientError
from benchmark_ycsb import YcsbWorkload


def test_client_read_response_types():
    """Verify RESP2 and RESP3 deserialization for various data types."""
    client = NexusClient()

    # Simple String
    client._rfile = io.BytesIO(b"+OK\r\n")
    assert client._read_response() == "OK"

    # Error
    client._rfile = io.BytesIO(b"-ERR syntax error\r\n")
    with pytest.raises(NexusClientError) as exc_info:
        client._read_response()
    assert "syntax error" in str(exc_info.value)

    # Integer
    client._rfile = io.BytesIO(b":42\r\n")
    assert client._read_response() == 42

    # Bulk String
    client._rfile = io.BytesIO(b"$5\r\nhello\r\n")
    assert client._read_response() == "hello"

    # Null Bulk String
    client._rfile = io.BytesIO(b"$-1\r\n")
    assert client._read_response() is None

    # Array
    client._rfile = io.BytesIO(b"*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n")
    assert client._read_response() == ["foo", "bar"]

    # RESP3 Boolean
    client._rfile = io.BytesIO(b"#t\r\n")
    assert client._read_response() is True

    # RESP3 Double
    client._rfile = io.BytesIO(b",3.14\r\n")
    assert client._read_response() == 3.14

    # RESP3 Null
    client._rfile = io.BytesIO(b"_\r\n")
    assert client._read_response() is None


def test_ycsb_workload_initialization():
    """Verify YCSB workload configuration parameters."""
    wl = YcsbWorkload(host="127.0.0.1", port=6379, workload_type="B", value_size_bytes=64)
    assert wl.workload_type == "B"
    assert len(wl.payload) == 64
    assert wl.keyspace_size == 10000
