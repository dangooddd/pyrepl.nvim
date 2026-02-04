import base64
import io
import os
from queue import Queue
from threading import Thread
from typing import Any, Optional, cast

import pynvim

IMAGE_MIME_TYPES = (
    "image/png",
    "image/jpeg",
    "image/svg+xml",
)

_nvim_queue: Queue[Optional[str]] = Queue()
_nvim_thread: Optional[Thread] = None


def _extract_image_data(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, (bytes, bytearray)):
        try:
            return bytes(value).decode("utf-8")
        except Exception:
            return ""
    if isinstance(value, (list, tuple)):
        if not value:
            return ""
        if isinstance(value[0], str):
            return "".join(cast(list[str], value))
        if isinstance(value[0], bytes):
            try:
                return b"".join(cast(list[bytes], value)).decode("utf-8")
            except Exception:
                return ""
        return _extract_image_data(value[0])
    return ""


def _prepare_image_data(image_mime: str, image_data: object) -> Optional[str]:
    if image_mime == "image/png" and isinstance(image_data, str):
        return image_data

    if image_mime == "image/svg+xml":
        try:
            import cairosvg
        except Exception:
            return None
        try:
            if isinstance(image_data, str):
                raw_svg = image_data.encode("utf-8")
            elif isinstance(image_data, (bytes, bytearray)):
                raw_svg = bytes(image_data)
            else:
                return None
            png_bytes = cairosvg.svg2png(bytestring=raw_svg)
            return base64.b64encode(png_bytes).decode("utf-8")
        except Exception:
            return None

    if isinstance(image_data, str):
        try:
            raw = base64.b64decode(image_data)
        except Exception:
            return None
    elif isinstance(image_data, (bytes, bytearray)):
        raw = bytes(image_data)
    else:
        return None

    if image_mime == "image/jpeg":
        try:
            from PIL import Image
        except Exception:
            return None
        try:
            img = Image.open(io.BytesIO(raw))
            output = io.BytesIO()
            img.save(output, format="PNG")
            return base64.b64encode(output.getvalue()).decode("utf-8")
        except Exception:
            return None

    if image_mime == "image/png":
        return base64.b64encode(raw).decode("utf-8")

    return None


def _nvim_worker() -> None:
    nvim: Optional[pynvim.Nvim] = None
    while True:
        data = _nvim_queue.get()
        try:
            if data is None:
                break

            address = os.environ.get("NVIM_LISTEN_ADDRESS")
            if not address:
                continue

            if nvim is None:
                try:
                    nvim = pynvim.attach("socket", path=address)
                except Exception:
                    nvim = None
                    continue

            escaped = data.replace("\\", "\\\\").replace('"', '\\"')
            try:
                nvim.command(
                    f'lua require("pyrepl.image").show_image_data("{escaped}")'
                )
            except Exception:
                nvim = None
        finally:
            _nvim_queue.task_done()


def _start_nvim_thread() -> None:
    global _nvim_thread
    if _nvim_thread and _nvim_thread.is_alive():
        return
    _nvim_thread = Thread(target=_nvim_worker, daemon=True)
    _nvim_thread.start()


def _send_image_to_nvim(data: str) -> None:
    _start_nvim_thread()
    _nvim_queue.put(data)


def handle_image(data: Any) -> bool:
    if not isinstance(data, dict):
        return False

    image_mime = None
    for candidate in IMAGE_MIME_TYPES:
        if candidate in data:
            image_mime = candidate
            break

    if not image_mime:
        return False

    image_data = _extract_image_data(data.get(image_mime))
    if not image_data:
        return False

    prepared = _prepare_image_data(image_mime, image_data)
    if not prepared:
        return False

    _send_image_to_nvim(prepared)
    return True
