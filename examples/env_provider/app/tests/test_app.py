import msgpack


def test_msgpack_roundtrip() -> None:
    data = {"hello": "world", "number": 42}
    packed = msgpack.packb(data)
    unpacked = msgpack.unpackb(packed)
    assert unpacked == data


def test_zenoh_import() -> None:
    import zenoh

    assert hasattr(zenoh, "open")
