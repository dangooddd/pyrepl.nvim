import argparse
import asyncio
import atexit
import base64
import io
import json
import os
import signal
import sys
import tempfile
import time
from queue import Empty, Queue
from threading import Lock, Thread
from typing import Any, Optional, cast

import pynvim
from jupyter_client.blocking.client import BlockingKernelClient
from PIL import Image
from prompt_toolkit.history import InMemoryHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.lexers import PygmentsLexer
from prompt_toolkit.shortcuts import PromptSession
from prompt_toolkit.styles.pygments import style_from_pygments_cls
from pygments.lexers.python import PythonLexer
from pygments.styles import get_style_by_name
from pygments.util import ClassNotFound

IMAGE_MIME_TYPES = (
    "image/png",
    "image/jpeg",
    "image/svg+xml",
)
sys.dont_write_bytecode = True


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
        elif isinstance(value[0], str):
            return "".join(cast(list[str], value))
        elif isinstance(value[0], bytes):
            try:
                return b"".join(cast(list[bytes], value)).decode("utf-8")
            except Exception:
                return ""
        return _extract_image_data(value[0])
    return ""


class REPLInterpreter:
    def __init__(
        self,
        connection_file: Optional[str] = None,
        image_debug: bool = False,
        auto_indent: bool = False,
        pygments_style: str = "default",
        session_id: Optional[int] = None,
    ):
        self.buffer: list[str] = []
        self.kernel_info = {}
        self.in_multiline = False

        self._pending_clearoutput = False
        self._executing = False
        self._execution_state = "idle"
        self._interrupt_requested = False
        self._image_debug = image_debug
        self._auto_indent = auto_indent
        self._pygments_style = pygments_style
        self._session_id = session_id
        self._temp_paths = set()

        try:
            self._temp_dir: Optional[tempfile.TemporaryDirectory[str]] = (
                tempfile.TemporaryDirectory(prefix="pyrepl-")
            )
        except Exception:
            self._temp_dir = None

        # Setup prompt toolkit
        self.history = InMemoryHistory()
        self.bindings = self._create_keybindings()
        self.lexer = PygmentsLexer(PythonLexer)
        self.nvim: Optional[pynvim.Nvim] = None
        self.nvim_queue: Queue[Optional[tuple[str, Any]]] = Queue()
        self.nvim_thread: Optional[Thread] = None
        self.nvim_lock = Lock()
        self.client: Optional[BlockingKernelClient] = None
        self._nvim_address = os.environ.get("NVIM_LISTEN_ADDRESS")

        if self._nvim_address:
            self._start_nvim_thread()

        self.session = PromptSession(
            history=self.history,
            key_bindings=self.bindings,
            enable_history_search=True,
            multiline=True,
            lexer=self.lexer,
            style=self._build_pygments_style(),
            prompt_continuation="... ",
            message=">>> ",
            include_default_pygments_style=True,
        )

        try:
            buffer = cast(Any, self.session.default_buffer)
            buffer.auto_indent = self._auto_indent
        except Exception:
            pass

        self._setup_signal_handlers()
        atexit.register(self._cleanup_resources)

        if connection_file:
            try:
                with open(connection_file, "r", encoding="utf-8") as f:
                    connection_info = json.load(f)
                client = BlockingKernelClient()
                client.load_connection_info(connection_info)
                client.start_channels()
                client.wait_for_ready(timeout=10)
                self.client = client
            except Exception as e:
                print(f"Failed to connect to kernel: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            print("No kernel connection file specified", file=sys.stderr)
            sys.exit(1)

    def _attach_nvim(self, log_failure=False):
        address = self._nvim_address or os.environ.get("NVIM_LISTEN_ADDRESS")

        if not address:
            self.nvim = None
            return False

        self._nvim_address = address

        try:
            self.nvim = pynvim.attach("socket", path=address)
            return True
        except Exception as e:
            self.nvim = None
            if log_failure:
                print(f"Failed to connect to Neovim: {e}", file=sys.stderr)
            return False

    def _ensure_nvim(self):
        if self.nvim:
            return True
        return self._attach_nvim(log_failure=self._image_debug)

    def _get_client(self) -> BlockingKernelClient:
        if self.client is None:
            raise RuntimeError("Kernel client is not initialized")
        return self.client

    def _interrupt_kernel(self) -> None:
        client = self._get_client()
        interrupt = getattr(client, "interrupt_kernel", None)
        if not callable(interrupt):
            raise AttributeError("Kernel client does not support interrupt_kernel")
        interrupt()

    def _is_nvim_disconnect_error(self, exc: Exception) -> bool:
        if isinstance(exc, (EOFError, BrokenPipeError, ConnectionResetError)):
            return True
        msg = str(exc).strip().lower()
        if msg in ("eof", "socket closed", "connection closed"):
            return True
        return "broken pipe" in msg or "connection reset" in msg

    def _handle_nvim_disconnect(self, exc: Exception, context: str) -> bool:
        if not self._is_nvim_disconnect_error(exc):
            return False
        self.nvim = None
        if self._image_debug:
            print(
                f"[pyrepl] Neovim connection closed during {context}.",
                file=sys.stderr,
            )
        return True

    def _start_nvim_thread(self):
        if not self._nvim_address:
            return
        if self.nvim_thread and self.nvim_thread.is_alive():
            return
        self.nvim_thread = Thread(target=self._nvim_worker, daemon=True)
        self.nvim_thread.start()

    def _vim_escape_string(self, value: str) -> str:
        return value.replace("\\", "\\\\").replace('"', '\\"')

    def _send_image_to_nvim(self, path: str) -> None:
        if not self._ensure_nvim():
            return
        escaped_path = self._vim_escape_string(path)
        try:
            with self.nvim_lock:
                nvim = cast(pynvim.Nvim, self.nvim)
                nvim.command(
                    f'lua require("pyrepl.image").show_image_file("{escaped_path}")'
                )
        except Exception as e:
            if self._handle_nvim_disconnect(e, "image sync"):
                return
            print(f"Error in Neovim thread: {e}", file=sys.stderr)

    def _create_keybindings(self) -> KeyBindings:
        kb = KeyBindings()

        @kb.add("enter")
        def _(event):
            b = event.current_buffer

            if b.document.text.strip():
                # Get the full text including the current line
                full_text = b.document.text

                # Check if the input is complete
                status, indent = self.handle_is_complete(full_text)

                if status == "incomplete":
                    self.in_multiline = True
                    event.current_buffer.newline()
                    if indent and self._auto_indent:
                        event.current_buffer.insert_text(indent)
                else:
                    event.current_buffer.validate_and_handle()
            else:
                if self.buffer:
                    event.current_buffer.newline()
                else:
                    self.in_multiline = False
                    event.current_buffer.validate_and_handle()

        @kb.add("c-c")
        def _(event):
            if self._executing:
                self._interrupt_requested = True
                try:
                    self._interrupt_kernel()
                except Exception as e:
                    print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
            else:
                print("\nKeyboardInterrupt")
                self.in_multiline = False
                event.current_buffer.reset()

        return kb

    async def interact_async(self) -> None:
        while True:
            try:
                if self._nvim_address:
                    self._start_nvim_thread()
                    self.nvim_queue.put(("repl_ready", None))
                # Get input with dynamic prompt
                code = await self.session.prompt_async()

                if code.strip() in ("exit", "quit"):
                    break

                if code.strip():
                    # Before execution, check if it's complete
                    status, _ = self.handle_is_complete(code)
                    if status == "incomplete":
                        self.in_multiline = True
                        self.buffer.append(code)
                        continue
                    else:
                        # If we have buffered content, include it
                        if self.buffer:
                            code = "\n".join(self.buffer + [code])
                            self.buffer.clear()
                        self.in_multiline = False
                        await self.handle_execute(code)

            except KeyboardInterrupt:
                self.in_multiline = False
                self.buffer.clear()
                continue

            except EOFError:
                break

        if self.client is not None:
            self.client.shutdown()
            self.client.stop_channels()

    def init_kernel_info(self) -> None:
        timeout = 10
        tic = time.time()
        client = self._get_client()
        msg_id = client.kernel_info()

        while True:
            try:
                reply = client.get_shell_msg(timeout=1)
                if reply["parent_header"].get("msg_id") == msg_id:
                    self.kernel_info = reply["content"]
                    return
            except Empty:
                if (time.time() - tic) > timeout:
                    raise RuntimeError("Kernel didn't respond to kernel_info_request")

    def _setup_signal_handlers(self) -> None:
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum: int, frame) -> None:
        if self._executing:
            self._interrupt_requested = True
            try:
                self._interrupt_kernel()
            except Exception as e:
                print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
        else:
            print("\nKeyboardInterrupt")

    def handle_is_complete(self, code: str) -> tuple[str, str]:
        client = self._get_client()
        while client.shell_channel.msg_ready():
            client.get_shell_msg()

        msg_id = client.is_complete(code)
        try:
            reply = client.get_shell_msg(timeout=0.5)
            if reply["parent_header"].get("msg_id") == msg_id:
                status = reply["content"]["status"]
                indent = reply["content"].get("indent", "")
                return status, indent
        except Empty:
            pass
        return "unknown", ""

    async def handle_execute(self, code: str) -> bool:
        self._interrupt_requested = False

        client = self._get_client()
        while client.shell_channel.msg_ready():
            client.get_shell_msg()

        msg_id = client.execute(code)
        self._executing = True
        self._execution_state = "busy"

        try:
            while self._execution_state != "idle" and client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    await self.handle_input_request(msg_id, timeout=0.05)
                except Empty:
                    await self.handle_iopub_msgs(msg_id)

                await asyncio.sleep(0.05)

            while client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    msg = client.get_shell_msg(timeout=0.05)
                    if msg["parent_header"].get("msg_id") == msg_id:
                        await self.handle_iopub_msgs(msg_id)
                        content = msg["content"]
                        # Set multiline to False only after execution is complete
                        self.in_multiline = False
                        return content["status"] == "ok"
                except Empty:
                    await asyncio.sleep(0.05)

        finally:
            self._executing = False
            self._interrupt_requested = False
            self.in_multiline = False  # Ensure it's set to False in case of errors

        return False

    def _build_pygments_style(self):
        style_name = self._pygments_style or "default"
        try:
            pygments_style = get_style_by_name(style_name)
        except ClassNotFound:
            print(
                f"Unknown Pygments style '{style_name}', falling back to 'default'.",
                file=sys.stderr,
            )
            pygments_style = get_style_by_name("default")
        return style_from_pygments_cls(pygments_style)

    async def handle_input_request(self, msg_id, timeout: float = 0.1) -> None:
        client = self._get_client()
        msg = client.get_stdin_msg(timeout=timeout)
        if msg_id == msg["parent_header"].get("msg_id"):
            content = msg["content"]
            try:
                raw_data = await self.session.prompt_async(content["prompt"])
                if not (
                    client.stdin_channel.msg_ready() or client.shell_channel.msg_ready()
                ):
                    client.input(raw_data)
            except (EOFError, KeyboardInterrupt):
                print("\n")
                return

    def interact(self) -> None:
        asyncio.run(self.interact_async())

    def _nvim_worker(self) -> None:
        """Worker thread for handling Neovim communications"""
        while True:
            try:
                data = self.nvim_queue.get()
                if data is None:
                    break
                try:
                    if isinstance(data, tuple) and len(data) == 2:
                        kind, payload = data
                    else:
                        kind, payload = "image", data

                    if kind == "repl_ready":
                        if not self._ensure_nvim():
                            continue
                        try:
                            with self.nvim_lock:
                                nvim = cast(pynvim.Nvim, self.nvim)
                                session_id = (
                                    str(self._session_id)
                                    if self._session_id is not None
                                    else ""
                                )
                                nvim.command(
                                    f'lua require("pyrepl")._on_repl_ready({session_id})'
                                )
                        except Exception as e:
                            if self._handle_nvim_disconnect(e, "repl_ready"):
                                continue
                            print(f"Error in Neovim thread: {e}", file=sys.stderr)
                        continue

                    if kind == "image_path":
                        if not self._ensure_nvim():
                            continue
                        if isinstance(payload, str) and payload:
                            self._send_image_to_nvim(payload)
                        continue

                    if kind != "image":
                        continue
                    image_mime = None
                    image_data = payload
                    if isinstance(payload, dict):
                        image_mime = payload.get("mime")
                        image_data = payload.get("data")

                    if not image_mime or not image_data:
                        continue

                    if not self._ensure_nvim():
                        continue
                    tmp_path = None

                    try:
                        suffix = ".png"
                        if image_mime == "image/jpeg":
                            suffix = ".jpg"
                        elif image_mime == "image/svg+xml":
                            suffix = ".svg"

                        if image_mime == "image/svg+xml":
                            if isinstance(image_data, str):
                                svg_text = image_data
                            elif isinstance(image_data, (bytes, bytearray)):
                                svg_text = bytes(image_data).decode("utf-8")
                            else:
                                svg_text = ""
                            if not svg_text:
                                continue
                            with tempfile.NamedTemporaryFile(
                                suffix=suffix,
                                delete=False,
                                dir=self._temp_dir.name if self._temp_dir else None,
                            ) as tmp:
                                tmp.write(svg_text.encode("utf-8"))
                                tmp_path = tmp.name
                        else:
                            if isinstance(image_data, str):
                                img_bytes = base64.b64decode(image_data)
                            elif isinstance(image_data, (bytes, bytearray)):
                                img_bytes = bytes(image_data)
                            else:
                                continue

                            with tempfile.NamedTemporaryFile(
                                suffix=suffix,
                                delete=False,
                                dir=self._temp_dir.name if self._temp_dir else None,
                            ) as tmp:
                                tmp.write(img_bytes)
                                tmp_path = tmp.name

                        if tmp_path:
                            self._register_temp_path(tmp_path)
                            if self._image_debug:
                                print(
                                    f"[pyrepl] wrote image temp: {tmp_path}",
                                    file=sys.stderr,
                                )
                            self._send_image_to_nvim(tmp_path)
                    except Exception as e:
                        print(f"Error handling image: {e}", file=sys.stderr)
                except Exception as e:
                    print(f"Error in Neovim thread: {e}", file=sys.stderr)
            except Exception as e:
                print(f"Error in Neovim worker: {e}", file=sys.stderr)
            finally:
                self.nvim_queue.task_done()

    def _cleanup(self) -> None:
        """Cleanup resources"""
        if self.nvim_thread and self.nvim_thread.is_alive():
            self.nvim_queue.put(None)  # Send exit signal
            self.nvim_thread.join(timeout=1.0)

    def _register_temp_path(self, path: Optional[str]) -> None:
        if path:
            self._temp_paths.add(path)

    def _write_image_file(self, image_mime: str, image_data: object) -> Optional[str]:
        if image_mime == "image/svg+xml":
            if self._image_debug:
                print(
                    "[pyrepl] svg images are not supported by the terminal backend",
                    file=sys.stderr,
                )
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

        temp_dir = self._temp_dir.name if self._temp_dir else None

        if image_mime == "image/jpeg":
            try:
                img = Image.open(io.BytesIO(raw))
                with tempfile.NamedTemporaryFile(
                    suffix=".png",
                    delete=False,
                    dir=temp_dir,
                ) as tmp:
                    img.save(tmp, format="PNG")
                    return tmp.name
            except Exception:
                return None

        if image_mime == "image/png":
            with tempfile.NamedTemporaryFile(
                suffix=".png",
                delete=False,
                dir=temp_dir,
            ) as tmp:
                tmp.write(raw)
                return tmp.name

        return None

    def _cleanup_temp_path(self, path: Optional[str]) -> None:
        if not path:
            return
        try:
            os.unlink(path)
        except Exception:
            pass
        self._temp_paths.discard(path)

    def _cleanup_temp_paths(self) -> None:
        for path in list(self._temp_paths):
            self._cleanup_temp_path(path)

    def _cleanup_resources(self) -> None:
        self._cleanup()
        self._cleanup_temp_paths()
        if self._temp_dir:
            try:
                self._temp_dir.cleanup()
            except Exception:
                pass
            self._temp_dir = None

    async def handle_iopub_msgs(self, msg_id) -> None:
        client = self._get_client()
        while client.iopub_channel.msg_ready():
            msg = client.get_iopub_msg()
            msg_type = msg["header"]["msg_type"]
            parent_id = msg["parent_header"].get("msg_id")

            if parent_id != msg_id:
                continue

            if msg_type == "status":
                self._execution_state = msg["content"]["execution_state"]

            elif msg_type == "stream":
                content = msg["content"]
                if self._pending_clearoutput:
                    sys.stdout.write("\r")
                    self._pending_clearoutput = False

                if content["name"] == "stdout":
                    sys.stdout.write(content["text"])
                    sys.stdout.flush()
                elif content["name"] == "stderr":
                    sys.stderr.write(content["text"])
                    sys.stderr.flush()

            elif msg_type in ("display_data", "execute_result"):
                if self._pending_clearoutput:
                    sys.stdout.write("\r")
                    self._pending_clearoutput = False

                content = msg["content"]
                data = content.get("data", {})

                if "text/plain" in data and not any(
                    mime in data for mime in IMAGE_MIME_TYPES
                ):
                    text = data.get("text/plain", "")
                    if isinstance(text, str):
                        text_output = text
                    else:
                        text_output = str(text[0]) if text else ""
                    print(text_output)
                    sys.stdout.flush()

                # Handle image data (prefer PNG for Neovim display)
                image_mime = None
                for candidate in IMAGE_MIME_TYPES:
                    if candidate in data:
                        image_mime = candidate
                        break

                if image_mime:
                    image_data = _extract_image_data(data.get(image_mime))
                    if not image_data:
                        continue
                    if self._image_debug:
                        print(
                            f"[pyrepl] image mime={image_mime} b64len={len(image_data)}",
                            file=sys.stderr,
                        )
                    if self._nvim_address:
                        tmp_path = self._write_image_file(image_mime, image_data)
                        if not tmp_path:
                            continue
                        self._register_temp_path(tmp_path)
                        if self._image_debug:
                            print(
                                f"[pyrepl] wrote image temp: {tmp_path}",
                                file=sys.stderr,
                            )
                        self._start_nvim_thread()
                        self.nvim_queue.put(("image_path", tmp_path))

            elif msg_type == "error":
                content = msg["content"]
                for frame in content["traceback"]:
                    print(frame, file=sys.stderr)
                sys.stderr.flush()

            elif msg_type == "clear_output":
                if msg["content"].get("wait", False):
                    self._pending_clearoutput = True
                else:
                    sys.stdout.write("\r")


ReplInterpreter = REPLInterpreter


def main():
    parser = argparse.ArgumentParser(description="Jupyter Console")

    parser.add_argument(
        "--connection-file",
        type=str,
        help="path to an existing kernel connection file.",
    )

    parser.add_argument(
        "--nvim-socket",
        type=str,
        help="Neovim socket address",
    )

    parser.add_argument(
        "--image-debug",
        action="store_true",
        help="Enable image debug logging",
    )

    parser.add_argument(
        "--auto-indent",
        action="store_true",
        help="Enable auto indentation in the prompt",
    )

    parser.add_argument(
        "--pygments-style",
        type=str,
        default="default",
        help="Pygments style name for REPL syntax highlighting",
    )

    parser.add_argument(
        "--session-id",
        type=int,
        help="Session id for REPL callbacks",
    )

    args = parser.parse_args()

    if args.nvim_socket:
        os.environ["NVIM_LISTEN_ADDRESS"] = args.nvim_socket

    interpreter = REPLInterpreter(
        connection_file=args.connection_file,
        image_debug=args.image_debug,
        auto_indent=args.auto_indent,
        pygments_style=args.pygments_style,
        session_id=args.session_id,
    )

    try:
        interpreter.interact()
    finally:
        interpreter._cleanup_resources()


if __name__ == "__main__":
    main()
