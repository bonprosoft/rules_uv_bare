import msgpack
from native_lib import add


def main() -> None:
    result = add(2, 3)
    print(f"2 + 3 = {result}")
    packed = msgpack.packb({"result": result})
    unpacked = msgpack.unpackb(packed)
    print(f"msgpack roundtrip: {unpacked}")
