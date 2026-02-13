from lib import greet


def test_greet():
    assert greet("world") == "Hello, world!"


def test_greet_custom():
    assert greet("Bazel") == "Hello, Bazel!"
