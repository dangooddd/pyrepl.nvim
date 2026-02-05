import base64
import io
import os
from enum import StrEnum
from queue import Queue
from threading import Thread
from typing import Any, Iterable, Optional, cast

import pynvim


class ImageMimeTypes(StrEnum):
    PNG = "image/png"
    JPG = "image/jpeg"
    SVG = "image/svg+xml"


_nvim_queue: Queue[Optional[str]] = Queue()
_nvim_thread: Optional[Thread] = None


def _flatten_sequence(value: Iterable[Any]) -> list[Any]:
    """Flatten nested lists and tuples into one list."""
    out: list[Any] = []
    for item in value:
        if isinstance(item, (list, tuple)):
            out.extend(_flatten_sequence(item))
        else:
            out.append(item)

    return out


def _to_text(value: Any) -> str:
    """Convert text-like values to a UTF-8 string."""
    if isinstance(value, str):
        return value

    if isinstance(value, (bytes, bytearray)):
        try:
            return bytes(value).decode("utf-8")
        except Exception:
            return ""

    return ""


def _extract_image_data(value: Any) -> str:
    """Extract image payload data as a single string."""
    if isinstance(value, (list, tuple)):
        flattened = _flatten_sequence(value)

        if not flattened:
            return ""

        if all(isinstance(item, str) for item in flattened):
            return "".join(cast(list[str], flattened))

        if all(isinstance(item, (bytes, bytearray)) for item in flattened):
            try:
                return b"".join(bytes(item) for item in flattened).decode("utf-8")
            except Exception:
                return ""

        return _extract_image_data(flattened[0])

    return _to_text(value)


def _prepare_image_data(image_mime: str, image_data: Any) -> Optional[str]:
    """Convert supported image payloads to base64-encoded PNG."""
    if image_mime == ImageMimeTypes.PNG:
        try:
            if isinstance(image_data, str):
                return image_data
            elif isinstance(image_data, bytes | bytearray):
                raw = bytes(image_data)
                return base64.b64encode(raw).decode("utf-8")
            else:
                return None
        except Exception:
            return None

    if image_mime == ImageMimeTypes.SVG:
        try:
            import cairosvg

            if isinstance(image_data, str):
                raw = image_data.encode("utf-8")
            elif isinstance(image_data, bytes | bytearray):
                raw = bytes(image_data)
            else:
                return None

            png_bytes = cairosvg.svg2png(bytestring=raw)
            return base64.b64encode(cast(bytes, png_bytes)).decode("utf-8")
        except Exception:
            return None

    if image_mime == ImageMimeTypes.JPG:
        try:
            from PIL import Image

            if isinstance(image_data, str):
                raw = base64.b64decode(image_data)
            elif isinstance(image_data, bytes | bytearray):
                raw = bytes(image_data)
            else:
                return None

            img = Image.open(io.BytesIO(raw))
            output = io.BytesIO()
            img.save(output, format="PNG")
            return base64.b64encode(output.getvalue()).decode("utf-8")
        except Exception:
            return None


def _get_nvim(
    address: Optional[str], current: Optional[pynvim.Nvim]
) -> Optional[pynvim.Nvim]:
    """Attach to Neovim via NVIM_LISTEN_ADDRESS if needed."""
    if not address:
        return None

    if current is not None:
        return current

    try:
        return pynvim.attach("socket", path=address)
    except Exception:
        return None


def _nvim_worker() -> None:
    """Worker thread that forwards image data to Neovim."""
    nvim: Optional[pynvim.Nvim] = None
    while True:
        data = _nvim_queue.get()
        try:
            if data is None:
                break

            address = os.environ.get("NVIM_LISTEN_ADDRESS")
            nvim = _get_nvim(address, nvim)
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
            _nvim_queue.task_done()


def _send_image_to_nvim(data: str) -> None:
    """Queue an image payload to be sent to Neovim."""
    global _nvim_thread

    if not _nvim_thread or not _nvim_thread.is_alive():
        _nvim_thread = Thread(target=_nvim_worker, daemon=True)
        _nvim_thread.start()

    _nvim_queue.put(data)


def handle_image(data: Any) -> bool:
    """Handle Jupyter image output and forward it to Neovim."""
    if not isinstance(data, dict):
        return False

    image_mime = None
    for candidate in ImageMimeTypes:
        if candidate in data:
            image_mime = candidate
            break

    if image_mime is None:
        return False

    image_data = _extract_image_data(data.get(image_mime))
    if not image_data:
        return False

    prepared = _prepare_image_data(image_mime, image_data)
    if not prepared:
        return False

    _send_image_to_nvim(prepared)
    return True
