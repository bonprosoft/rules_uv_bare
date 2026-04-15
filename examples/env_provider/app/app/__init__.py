import msgpack
from pydantic_core import SchemaValidator, core_schema


def run() -> None:
    data = {"hello": "world", "number": 42}
    packed = msgpack.packb(data)
    unpacked = msgpack.unpackb(packed)
    print(f"Original:  {data}")
    print(f"Packed:    {packed!r} ({len(packed)} bytes)")
    print(f"Unpacked:  {unpacked}")

    validator = SchemaValidator(core_schema.int_schema())
    print(f"pydantic-core validated int: {validator.validate_python(42)}")
