import msgpack
import zenoh


def run() -> None:
    data = {"hello": "world", "number": 42}
    packed = msgpack.packb(data)
    unpacked = msgpack.unpackb(packed)
    print(f"Original:  {data}")
    print(f"Packed:    {packed!r} ({len(packed)} bytes)")
    print(f"Unpacked:  {unpacked}")
    print(f"Zenoh available: {hasattr(zenoh, 'open')}")
