import argparse
import os
import sys

from jupyter_console.app import ZMQTerminalIPythonApp
from traitlets.config import Config

sys.dont_write_bytecode = True


def _ensure_package_root() -> None:
    package_root = os.path.dirname(os.path.dirname(__file__))
    if package_root not in sys.path:
        sys.path.insert(0, package_root)


def main() -> None:
    parser = argparse.ArgumentParser(description="PyREPL Jupyter Console")
    parser.add_argument(
        "--connection-file",
        type=str,
        required=True,
        help="path to an existing kernel connection file.",
    )
    parser.add_argument(
        "--pygments-style",
        type=str,
        default="default",
        help="Pygments style name for REPL syntax highlighting",
    )
    args, extra = parser.parse_known_args()

    _ensure_package_root()

    from pyrepl.extension import handle_image

    config = Config()
    config.ZMQTerminalInteractiveShell.image_handler = "callable"
    config.ZMQTerminalInteractiveShell.callable_image_handler = handle_image
    config.ZMQTerminalInteractiveShell.highlighting_style = args.pygments_style

    app = ZMQTerminalIPythonApp.instance(config=config)
    app.initialize(["--existing", args.connection_file, *extra])
    app.start()  # type: ignore


if __name__ == "__main__":
    main()
