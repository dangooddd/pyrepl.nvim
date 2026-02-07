import argparse
import os
import sys
from typing import Any, Callable

from jupyter_console.app import ZMQTerminalIPythonApp
from traitlets.config import Config


def _ensure_package_root() -> None:
    """Add the pyrepl package root to sys.path."""
    package_root = os.path.dirname(os.path.dirname(__file__))
    if package_root not in sys.path:
        sys.path.insert(0, package_root)


def _build_config(
    pygments_style: str,
    image_handler: Callable[[Any], bool],
) -> Config:
    """Build a traitlets Config for the Jupyter console."""
    config = Config()
    config.ZMQTerminalInteractiveShell.image_handler = "callable"
    config.ZMQTerminalInteractiveShell.callable_image_handler = image_handler
    config.ZMQTerminalInteractiveShell.highlighting_style = pygments_style
    return config


def _parse_args() -> tuple[argparse.Namespace, list[str]]:
    """Parse command-line arguments for the console wrapper."""
    parser = argparse.ArgumentParser(description="Pyrepl Jupyter Console")
    parser.add_argument(
        "--pygments-style",
        type=str,
        default="default",
        help="Pygments style name for REPL syntax highlighting",
    )
    return parser.parse_known_args()


def main() -> None:
    """Run the Jupyter console attached to an existing kernel."""
    args, extra = _parse_args()
    _ensure_package_root()

    from pyrepl.extension import handle_image

    config = _build_config(args.pygments_style, handle_image)
    app = ZMQTerminalIPythonApp.instance(config=config)
    app.initialize([*extra])
    app.start()  # type: ignore


if __name__ == "__main__":
    main()
