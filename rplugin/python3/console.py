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
from typing import Optional, cast

import pynvim
from jupyter_client import BlockingKernelClient
from PIL import Image
from prompt_toolkit import print_formatted_text
from prompt_toolkit.formatted_text import ANSI, HTML
from prompt_toolkit.history import InMemoryHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.lexers import PygmentsLexer
from prompt_toolkit.shortcuts import PromptSession
from prompt_toolkit.styles import Style
from pygments.lexers.python import PythonLexer

IMAGE_MIME_TYPES = (
    "image/png",
    "image/jpeg",
    "image/svg+xml",
)
sys.dont_write_bytecode = True


def _gradient_ansi_lines(lines, start, end):
    if not lines:
        return ""
    if len(lines) == 1:
        colors = [start]
    else:
        colors = []
        for idx in range(len(lines)):
            ratio = idx / (len(lines) - 1)
            r = int(start[0] + (end[0] - start[0]) * ratio)
            g = int(start[1] + (end[1] - start[1]) * ratio)
            b = int(start[2] + (end[2] - start[2]) * ratio)
            colors.append((r, g, b))
    colored = []
    for line, (r, g, b) in zip(lines, colors):
        colored.append(f"\x1b[38;2;{r};{g};{b}m{line}\x1b[0m")
    return "\n".join(colored)


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


def _read_env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except Exception:
        return default
    return value if value > 0 else default


def _read_env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = float(raw)
    except Exception:
        return default
    if value <= 0:
        return default
    return min(value, 1.0)


class ReplInterpreter:
    def __init__(
        self, connection_file: Optional[str] = None, lan: Optional[str] = None
    ):
        self.buffer: list[str] = []
        self._pending_clearoutput = False
        self._executing = False
        self._execution_state = "idle"
        self.kernel_info = {}
        self.in_multiline = False
        self._interrupt_requested = False
        self._image_debug = os.environ.get("PYROLA_IMAGE_DEBUG", "0") == "1"
        self._auto_indent = os.environ.get("PYROLA_AUTO_INDENT", "0") == "1"
        self._cell_width = _read_env_int("PYROLA_IMAGE_CELL_WIDTH", 10)
        self._cell_height = _read_env_int("PYROLA_IMAGE_CELL_HEIGHT", 20)
        self._image_max_width_ratio = _read_env_float(
            "PYROLA_IMAGE_MAX_WIDTH_RATIO", 0.5
        )
        self._image_max_height_ratio = _read_env_float(
            "PYROLA_IMAGE_MAX_HEIGHT_RATIO", 0.5
        )
        self._temp_paths = set()
        try:
            self._temp_dir = tempfile.TemporaryDirectory(prefix="pyrola-")
        except Exception:
            self._temp_dir = None

        # Setup prompt toolkit
        self.history = InMemoryHistory()
        self.bindings = self._create_keybindings()

        self.lexer = PygmentsLexer(PythonLexer)

        self.nvim = None
        self.nvim_queue = Queue()
        self.nvim_thread = None
        self.nvim_lock = Lock()
        self._nvim_address = os.environ.get("NVIM_LISTEN_ADDRESS")

        if self._nvim_address:
            self._start_nvim_thread()

        self.style = Style.from_dict(
            {
                # Basic colors
                "continuation": "#ff8c00",
                # Use RGB colors for better compatibility
                "pygments.keyword": "#569cd6",
                "pygments.string": "#ce9178",
                "pygments.number": "#b5cea8",
                "pygments.comment": "#6a9955",
                "pygments.operator": "#d4d4d4",
                "pygments.name.function": "#1f86d6",
                "pygments.name.class": "#4ec9b0",
                "pygments.text": "#d4d4d4",
                "pygments.name": "#f5614a",
                "pygments.name.builtin": "#569cd6",
                "pygments.punctuation": "#d4d4d4",
                "pygments.name.namespace": "#4ec9b0",
                "pygments.name.decorator": "#c586c0",
                "pygments.name.exception": "#f44747",
                "pygments.name.constant": "#4fc1ff",
            }
        )

        def continuation_prompt(width, line_number, is_soft_wrap):
            return HTML("<orange>.. </orange>")

        self.session = PromptSession(
            history=self.history,
            key_bindings=self.bindings,
            enable_history_search=True,
            multiline=True,
            style=self.style,
            lexer=self.lexer,  # Add the lexer here
            prompt_continuation=continuation_prompt,
            message=lambda: HTML("<orange>>> </orange>"),
            include_default_pygments_style=False,
        )
        try:
            self.session.default_buffer.auto_indent = self._auto_indent
        except Exception:
            pass

        self._setup_signal_handlers()
        atexit.register(self._cleanup_resources)

        if connection_file:
            try:
                with open(connection_file, "r", encoding="utf-8") as f:
                    connection_info = json.load(f)
                self.client = BlockingKernelClient()
                self.client.load_connection_info(connection_info)
                self.client.start_channels()
                self.client.wait_for_ready(timeout=10)
                self.kernelname = connection_info.get("kernel_name")
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
                f"[pyrola] Neovim connection closed during {context}.",
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

    def _send_image_to_nvim(
        self, path: str, width: Optional[int], height: Optional[int]
    ) -> None:
        if not self._ensure_nvim():
            return
        escaped_path = self._vim_escape_string(path)
        width_val = int(width) if width else 0
        height_val = int(height) if height else 0
        try:
            with self.nvim_lock:
                self.nvim.command(f'let g:pyrola_image_path = "{escaped_path}"')
                self.nvim.command(f"let g:pyrola_image_width = {width_val}")
                self.nvim.command(f"let g:pyrola_image_height = {height_val}")
                self.nvim.command(
                    'lua require("pyrola.image").show_image_file(vim.g.pyrola_image_path, vim.g.pyrola_image_width, vim.g.pyrola_image_height)'
                )
                self.nvim.command("unlet g:pyrola_image_path")
                self.nvim.command("unlet g:pyrola_image_width")
                self.nvim.command("unlet g:pyrola_image_height")
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
                    self.client.interrupt_kernel()
                except Exception as e:
                    print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
            else:
                print("\nKeyboardInterrupt")
                self.in_multiline = False
                event.current_buffer.reset()

        return kb

    async def interact_async(self, banner: Optional[str] = None) -> None:
        logo_lines = [
            "██████╗ ██╗   ██╗██████╗  ██████╗ ██╗      █████╗ ",
            "██╔══██╗╚██╗ ██╔╝██╔══██╗██╔═══██╗██║     ██╔══██╗",
            "██████╔╝ ╚████╔╝ ██████╔╝██║   ██║██║     ███████║",
            "██╔═══╝   ╚██╔╝  ██╔══██╗██║   ██║██║     ██╔══██║",
            "██║        ██║   ██║  ██║╚██████╔╝███████╗██║  ██║",
            "╚═╝        ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝",
        ]
        logo = _gradient_ansi_lines(logo_lines, (255, 196, 107), (255, 108, 0))
        print_formatted_text(ANSI(logo))
        print_formatted_text(
            HTML(
                f"<orange>\n    Welcome to Pyrola! kernel</orange> <ansired>{self.kernelname}</ansired> <orange>initialized!\n</orange>"
            ),
            style=self.style,
        )

        while True:
            try:
                if self._nvim_address:
                    self._start_nvim_thread()
                    self.nvim_queue.put(("repl_ready", None))
                # Get input with dynamic prompt
                code = await self.session.prompt_async()

                if code.strip() in ("exit", "quit"):
                    print_formatted_text(
                        HTML("<orange>Shutting down kernel...</orange>"),
                        style=self.style,
                    )
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

        if hasattr(self, "client") and self.client is not None:
            self.client.shutdown()
            self.client.stop_channels()

    def init_kernel_info(self) -> None:
        timeout = 10
        tic = time.time()
        msg_id = self.client.kernel_info()

        while True:
            try:
                reply = self.client.get_shell_msg(timeout=1)
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
                self.client.interrupt_kernel()
            except Exception as e:
                print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
        else:
            print("\nKeyboardInterrupt")

    def handle_is_complete(self, code: str) -> tuple[str, str]:
        while self.client.shell_channel.msg_ready():
            self.client.get_shell_msg()

        msg_id = self.client.is_complete(code)
        try:
            reply = self.client.get_shell_msg(timeout=0.5)
            if reply["parent_header"].get("msg_id") == msg_id:
                status = reply["content"]["status"]
                indent = reply["content"].get("indent", "")
                return status, indent
        except Empty:
            pass
        return "unknown", ""

    async def handle_execute(self, code: str) -> bool:
        self._interrupt_requested = False

        while self.client.shell_channel.msg_ready():
            self.client.get_shell_msg()

        msg_id = self.client.execute(code)
        self._executing = True
        self._execution_state = "busy"

        try:
            while self._execution_state != "idle" and self.client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    await self.handle_input_request(msg_id, timeout=0.05)
                except Empty:
                    await self.handle_iopub_msgs(msg_id)

                await asyncio.sleep(0.05)

            while self.client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    msg = self.client.get_shell_msg(timeout=0.05)
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

    async def handle_input_request(self, msg_id, timeout: float = 0.1) -> None:
        msg = self.client.get_stdin_msg(timeout=timeout)
        if msg_id == msg["parent_header"].get("msg_id"):
            content = msg["content"]
            try:
                raw_data = await self.session.prompt_async(content["prompt"])
                if not (
                    self.client.stdin_channel.msg_ready()
                    or self.client.shell_channel.msg_ready()
                ):
                    self.client.input(raw_data)
            except (EOFError, KeyboardInterrupt):
                print("\n")
                return

    def interact(self, banner: Optional[str] = None) -> None:
        asyncio.run(self.interact_async(banner))

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
                                self.nvim.command(
                                    'lua require("pyrola")._on_repl_ready()'
                                )
                        except Exception as e:
                            if self._handle_nvim_disconnect(e, "repl_ready"):
                                continue
                            print(f"Error in Neovim thread: {e}", file=sys.stderr)
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
                    try:
                        with self.nvim_lock:
                            dimensions = {
                                "width": self.nvim.lua.vim.api.nvim_get_option(
                                    "columns"
                                ),
                                "height": self.nvim.lua.vim.api.nvim_get_option(
                                    "lines"
                                ),
                            }
                    except Exception as e:
                        if self._handle_nvim_disconnect(e, "image sync"):
                            continue
                        print(f"Error in Neovim thread: {e}", file=sys.stderr)
                        continue

                    target_width = max(
                        1,
                        int(
                            dimensions["width"]
                            * self._cell_width
                            * self._image_max_width_ratio
                        ),
                    )
                    target_height = max(
                        1,
                        int(
                            dimensions["height"]
                            * self._cell_height
                            * self._image_max_height_ratio
                        ),
                    )

                    tmp_path = None
                    new_width = None
                    new_height = None

                    try:
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
                                suffix=".svg",
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

                            img = Image.open(io.BytesIO(img_bytes))
                            orig_width, orig_height = img.size

                            if (
                                orig_width > target_width
                                or orig_height > target_height
                                or orig_width < target_width / 2
                                or orig_height < target_height / 2
                            ):
                                width_ratio = target_width / orig_width
                                height_ratio = target_height / orig_height
                                ratio = min(width_ratio, height_ratio)
                                new_width = int(orig_width * ratio)
                                new_height = int(orig_height * ratio)
                                img = img.resize(
                                    (new_width, new_height), Image.Resampling.LANCZOS
                                )
                            else:
                                new_width = orig_width
                                new_height = orig_height

                            with tempfile.NamedTemporaryFile(
                                suffix=".png",
                                delete=False,
                                dir=self._temp_dir.name if self._temp_dir else None,
                            ) as tmp:
                                img.save(tmp, format="PNG")
                                tmp_path = tmp.name

                        if tmp_path:
                            self._register_temp_path(tmp_path)
                            if self._image_debug:
                                print(
                                    f"[pyrola] wrote image temp: {tmp_path}",
                                    file=sys.stderr,
                                )
                            self._send_image_to_nvim(tmp_path, new_width, new_height)
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
        while self.client.iopub_channel.msg_ready():
            msg = self.client.get_iopub_msg()
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
                            f"[pyrola] image mime={image_mime} b64len={len(image_data)}",
                            file=sys.stderr,
                        )
                    if self._nvim_address:
                        self._start_nvim_thread()
                        self.nvim_queue.put(
                            ("image", {"mime": image_mime, "data": image_data})
                        )

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


def main():
    parser = argparse.ArgumentParser(description="Jupyter Console")
    parser.add_argument("--existing", type=str, help="an existing kernel full path.")
    parser.add_argument("--filetype", type=str, help="language name based filetype.")
    parser.add_argument("--nvim-socket", type=str, help="Neovim socket address")
    args = parser.parse_args()

    # Set NVIM_LISTEN_ADDRESS environment variable
    if args.nvim_socket:
        os.environ["NVIM_LISTEN_ADDRESS"] = args.nvim_socket

    interpreter = ReplInterpreter(connection_file=args.existing, lan=args.filetype)
    try:
        interpreter.interact()
    finally:
        interpreter._cleanup_resources()


if __name__ == "__main__":
    main()
