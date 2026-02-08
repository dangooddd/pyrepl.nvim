import sys
from pathlib import Path

from jupyter_console.app import ZMQTerminalIPythonApp
from traitlets.config import Config


def main() -> None:
    """Run the Jupyter console with pyrepl integration."""
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from pyrepl.extension import handle_image

    config = Config()
    config.ZMQTerminalInteractiveShell.image_handler = "callable"
    config.ZMQTerminalInteractiveShell.callable_image_handler = handle_image
    app = ZMQTerminalIPythonApp.instance(config=config)
    app.initialize(sys.argv[1:])
    app.start()  # type: ignore


if __name__ == "__main__":
    main()
