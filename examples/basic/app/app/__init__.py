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
@click.option(
    "--config",
    type=click.Path(exists=True),
    default=None,
    help="Path to config JSON (default: bundled config).",
)
def run(a: int | None, b: int | None, config: str | None) -> None:
    config_path = (
        Path(config) if config else Path(__file__).parent / "data" / "config.json"
    )
    cfg = json.loads(config_path.read_text())
    a = a if a is not None else cfg["a"]
    b = b if b is not None else cfg["b"]
    result = add(a, b)
    click.echo(f"{a} + {b} = {result}")
