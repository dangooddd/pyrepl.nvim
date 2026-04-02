import base64
import io
import json
import os
from argparse import ArgumentParser
from queue import Queue
from threading import Event, Thread
from typing import Any

import pynvim
from jupyter_console.app import ZMQTerminalIPythonApp
from prompt_toolkit.styles import defaults as ptk_defaults
from traitlets.config import Config

PNG = "image/png"
JPG = "image/jpeg"
SVG = "image/svg+xml"


def log(msg: str):
    return f"[pyrepl] {msg}"


def normalize_payload(payload: Any) -> str | None:
    """Normalize image payload to a single string."""
    if isinstance(payload, str) and payload:
        return payload

    if (
        isinstance(payload, list)
        and payload
        and all(isinstance(item, str) for item in payload)
    ):
        combined = "".join(payload)
        if combined:
            return combined

    return None


def pick_image_payload(data: dict[str, Any]) -> tuple[str, str] | None:
    """Pick first supported image payload in preferred order."""
    for image_mime in (PNG, JPG, SVG):
        payload = normalize_payload(data.get(image_mime))
        if payload:
            return image_mime, payload

    return None


def convert_image_to_png_base64(image_mime: str, image_data: str) -> str | None:
    """Convert supported image payloads to base64-encoded PNG."""
    if image_mime == PNG:
        return image_data

    if image_mime == SVG:
        try:
            import cairosvg

            raw = image_data.encode("utf-8")
            png_bytes = cairosvg.svg2png(bytestring=raw)
            return base64.b64encode(png_bytes).decode("utf-8")
        except Exception:
            return None

    if image_mime == JPG:
        try:
            from PIL import Image

            raw = base64.b64decode(image_data)
            img = Image.open(io.BytesIO(raw)).convert("RGBA")
            output = io.BytesIO()
            img.save(output, format="PNG")
            return base64.b64encode(output.getvalue()).decode("utf-8")

        except Exception:
            return None

    return None


def image_pipeline(data: Any):
    """Handle Jupyter image output and forward it to Neovim."""
    if not isinstance(data, dict):
        return None

    selected = pick_image_payload(data)
    if selected is None:
        return None
    image_mime, image_data = selected

    return convert_image_to_png_base64(image_mime, image_data)


def image_worker(queue: Queue, dead: Event, nvim: pynvim.Nvim):
    """Main thread worker to handle image display in nvim."""
    try:
        while True:
            data = queue.get()

            try:
                nvim.exec_lua("require('pyrepl.image').console_endpoint(...)", data)
            except Exception as e:
                print(log(f"failed to display image: {e}"))
            finally:
                queue.task_done()

    except Exception as e:
        print(log(f"image worker is dead {e}"))
        dead.set()


def main() -> None:
    """Run the Jupyter console with pyrepl integration."""
    path = os.environ.get("NVIM")
    assert path is not None

    nvim = pynvim.attach("socket", path=path)
    queue = Queue()
    dead = Event()
    thread = Thread(target=image_worker, args=(queue, dead, nvim), daemon=True)

    def image_handler(data):
        if dead.is_set():
            return False

        data = image_pipeline(data)
        if data is None:
            return False

        queue.put(data)
        return True

    config = Config()
    config.ZMQTerminalInteractiveShell.image_handler = "callable"
    config.ZMQTerminalInteractiveShell.callable_image_handler = image_handler
    app = ZMQTerminalIPythonApp.instance(config=config)

    parser = ArgumentParser("Pyrepl console.", add_help=False)
    parser.add_argument("--prompt-toolkit-overrides", type=str, default=None)
    known, args = parser.parse_known_args()

    try:
        app.initialize(args)

        if known.prompt_toolkit_overrides is not None:
            overrides = dict(ptk_defaults.PROMPT_TOOLKIT_STYLE)
            overrides.update(json.loads(known.prompt_toolkit_overrides))
            ptk_defaults.PROMPT_TOOLKIT_STYLE[:] = list(overrides.items())

        thread.start()
        app.start()  # type: ignore

    except Exception as e:
        nvim.exec_lua("vim.notify(..., vim.log.levels.ERROR)", log(str(e)))


if __name__ == "__main__":
    main()
