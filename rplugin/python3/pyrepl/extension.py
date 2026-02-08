import base64
import io
import os
from enum import StrEnum
from queue import Queue
from threading import Thread
from typing import Any, Optional

import pynvim


class ImageMimeTypes(StrEnum):
    PNG = "image/png"
    JPG = "image/jpeg"
    SVG = "image/svg+xml"


nvim_queue: Queue[Optional[str]] = Queue()
nvim_thread: Optional[Thread] = None


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
            img = Image.open(io.BytesIO(raw))
            output = io.BytesIO()
            img.save(output, format="PNG")
            return base64.b64encode(output.getvalue()).decode("utf-8")
        except Exception:
            return None

    return None


def get_nvim(
    address: Optional[str], current: Optional[pynvim.Nvim]
) -> Optional[pynvim.Nvim]:
    """Attach to Neovim via NVIM if needed."""
    if not address:
        return None

    if current is not None:
        return current

    try:
        return pynvim.attach("socket", path=address)
    except Exception:
        return None


def nvim_worker() -> None:
    """Worker thread that forwards image data to Neovim."""
    nvim: Optional[pynvim.Nvim] = None
    while True:
        data = nvim_queue.get()
        try:
            if data is None:
                break

            address = os.environ.get("NVIM")
            nvim = get_nvim(address, nvim)
            if nvim is None:
                continue

            try:
                nvim.exec_lua(
                    'require("pyrepl.image").show_image_data(...)',
                    data,
                )
            except Exception:
                nvim = None
        finally:
            nvim_queue.task_done()


def send_image_to_nvim(data: str) -> None:
    """Queue an image payload to be sent to Neovim."""
    global nvim_thread

    if not nvim_thread or not nvim_thread.is_alive():
        nvim_thread = Thread(target=nvim_worker, daemon=True)
        nvim_thread.start()

    nvim_queue.put(data)


def handle_image(data: Any) -> bool:
    """Handle Jupyter image output and forward it to Neovim."""
    if not isinstance(data, dict):
        return False

    selected = pick_image_payload(data)
    if not selected:
        return False
    image_mime, image_data = selected

    prepared = convert_image_to_png_base64(image_mime, image_data)
    if not prepared:
        return False

    send_image_to_nvim(prepared)
    return True
