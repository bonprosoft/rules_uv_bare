import msgpack


def test_msgpack_roundtrip() -> None:
    data = {"hello": "world", "number": 42}
    packed = msgpack.packb(data)
    unpacked = msgpack.unpackb(packed)
    assert unpacked == data


def test_pydantic_core_validate() -> None:
    from pydantic_core import SchemaValidator, core_schema

    validator = SchemaValidator(core_schema.int_schema())
    assert validator.validate_python(42) == 42
