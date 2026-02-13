import json
from pathlib import Path

import click
from lib import add


@click.command()
@click.option(
    "--a",
    type=int,
    default=None,
    help="Override the first operand from config.",
)
@click.option(
    "--b",
    type=int,
    default=None,
    help="Override the second operand from config.",
)
def run(a: int | None, b: int | None) -> None:
    config_path = Path(__file__).parent / "data" / "config.json"
    config = json.loads(config_path.read_text())
    a = a if a is not None else config["a"]
    b = b if b is not None else config["b"]
    result = add(a, b)
    click.echo(f"{a} + {b} = {result}")
