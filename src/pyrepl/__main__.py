import base64
import io
import os
import sys
from enum import StrEnum
from functools import partial
from queue import Empty, Queue
from threading import Event, Lock, Thread
from typing import Any, Optional

import pynvim
from jupyter_console.app import ZMQTerminalIPythonApp
from traitlets.config import Config

queue = Queue()
dead = Event()


class ImageMimeTypes(StrEnum):
    PNG = "image/png"
    JPG = "image/jpeg"
    SVG = "image/svg+xml"


def worker():
    """Main thread worker to handle image display in nvim."""
    addr = os.environ.get("NVIM")
    lua_command = "require('pyrepl.image').show_image_data(...)"

    if addr is None:
        dead.set()
        return

    try:
        with pynvim.attach("socket", path=os.environ.get("NVIM", "")) as nvim:
            while True:
                try:
                    data = queue.get()
                    nvim.exec_lua(lua_command, data, async_=False)
                finally:
                    queue.task_done()
    except Exception:
        dead.set()


def normalize_payload(payload: Any) -> Optional[str]:
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


def pick_image_payload(data: dict[str, Any]) -> Optional[tuple[ImageMimeTypes, str]]:
    """Pick first supported image payload in preferred order."""
    for image_mime in (ImageMimeTypes.PNG, ImageMimeTypes.JPG, ImageMimeTypes.SVG):
        payload = normalize_payload(data.get(image_mime))
        if payload:
            return image_mime, payload

    return None


def convert_image_to_png_base64(
    image_mime: ImageMimeTypes,
    image_data: str,
) -> Optional[str]:
    """Convert supported image payloads to base64-encoded PNG."""
    if image_mime == ImageMimeTypes.PNG:
        return image_data

    if image_mime == ImageMimeTypes.SVG:
        try:
            import cairosvg

            raw = image_data.encode("utf-8")
            png_bytes = cairosvg.svg2png(bytestring=raw)
            if not isinstance(png_bytes, (bytes, bytearray)):
                return None
            return base64.b64encode(png_bytes).decode("utf-8")
        except Exception:
            return None

    if image_mime == ImageMimeTypes.JPG:
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


def image_handler(data: Any):
    """Handle Jupyter image output and forward it to Neovim."""
    if dead.is_set():
        return

    if not isinstance(data, dict):
        return

    selected = pick_image_payload(data)
    if not selected:
        return
    image_mime, image_data = selected

    prepared = convert_image_to_png_base64(image_mime, image_data)
    if not prepared:
        return

    queue.put(prepared)


def main() -> None:
    """Run the Jupyter console with pyrepl integration."""
    config = Config()
    config.ZMQTerminalInteractiveShell.image_handler = "callable"
    config.ZMQTerminalInteractiveShell.callable_image_handler = image_handler

    app = ZMQTerminalIPythonApp.instance(config=config)
    app.initialize(sys.argv[1:])

    thread = Thread(target=worker, name="nvim-pipe", daemon=True)
    thread.start()
    app.start()  # type: ignore


if __name__ == "__main__":
    main()
