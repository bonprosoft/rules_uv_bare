import msgpack
from native_lib import add


def test_add():
    assert add(2, 3) == 5


def test_add_negative():
    assert add(-1, 1) == 0


def test_msgpack_roundtrip():
    data = {"result": add(2, 3)}
    assert msgpack.unpackb(msgpack.packb(data)) == data
