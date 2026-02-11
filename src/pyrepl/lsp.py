#!/usr/bin/env python3
from __future__ import annotations

import argparse
import bisect
import json
import sys
import time
from pathlib import Path
from queue import Empty
from typing import Any
from urllib.parse import unquote, urlparse

from jupyter_client import BlockingKernelClient


def log(msg: str) -> None:
    sys.stderr.write(f"[pyrepl-lsp] {msg}\n")
    sys.stderr.flush()


def read_lsp_message() -> dict[str, Any] | None:
    headers: dict[str, str] = {}

    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break

        try:
            key, value = line.decode("ascii").split(":", 1)
        except ValueError:
            continue
        headers[key.strip().lower()] = value.strip()

    raw_len = headers.get("content-length")
    if raw_len is None:
        return None

    try:
        length = int(raw_len)
    except ValueError:
        return None

    body = sys.stdin.buffer.read(length)
    if len(body) != length:
        return None

    return json.loads(body.decode("utf-8"))


def send_lsp_message(payload: dict[str, Any]) -> None:
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
    sys.stdout.buffer.write(header)
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


class LspError(Exception):
    def __init__(self, code: int, message: str, data: Any = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


def line_starts(text: str) -> list[int]:
    starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def utf16_units(ch: str) -> int:
    return 2 if ord(ch) > 0xFFFF else 1


def position_to_offset(text: str, line: int, character_utf16: int) -> int:
    if line < 0:
        return 0

    starts = line_starts(text)
    if line >= len(starts):
        return len(text)

    line_start = starts[line]
    line_end = starts[line + 1] if line + 1 < len(starts) else len(text)

    line_text = text[line_start:line_end]
    if line_text.endswith("\n"):
        line_text = line_text[:-1]
    if line_text.endswith("\r"):
        line_text = line_text[:-1]

    want = max(character_utf16, 0)
    cur = 0
    py_col = 0
    for ch in line_text:
        step = utf16_units(ch)
        if cur + step > want:
            break
        cur += step
        py_col += 1

    return line_start + py_col


def offset_to_position(text: str, offset: int) -> dict[str, int]:
    offset = max(0, min(offset, len(text)))
    starts = line_starts(text)
    line = bisect.bisect_right(starts, offset) - 1
    if line < 0:
        line = 0

    line_start = starts[line]
    line_end = starts[line + 1] if line + 1 < len(starts) else len(text)

    line_text = text[line_start:line_end]
    if line_text.endswith("\n"):
        line_text = line_text[:-1]
    if line_text.endswith("\r"):
        line_text = line_text[:-1]

    py_col = min(offset - line_start, len(line_text))
    character = 0
    for ch in line_text[:py_col]:
        character += utf16_units(ch)

    return {"line": line, "character": character}


def uri_to_path(uri: str) -> Path | None:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return None

    path = unquote(parsed.path)
    if sys.platform.startswith("win") and path.startswith("/"):
        path = path[1:]
    return Path(path)


class KernelCompleter:
    def __init__(self, connection_file: str, timeout: float) -> None:
        self.timeout = timeout
        self.client = BlockingKernelClient(connection_file=connection_file)
        self.client.load_connection_file()
        self.client.start_channels()

        try:
            self.client.wait_for_ready(timeout=timeout)
        except Exception as exc:
            log(f"wait_for_ready warning: {exc!r}")

    def close(self) -> None:
        try:
            self.client.stop_channels()
        except Exception:
            pass

    def complete(self, code: str, cursor_pos: int) -> tuple[list[str], int, int]:
        msg_id = self.client.complete(code=code, cursor_pos=cursor_pos)
        deadline = time.monotonic() + self.timeout

        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("kernel complete timeout")

            try:
                msg = self.client.get_shell_msg(timeout=left)
            except Empty as exc:
                raise TimeoutError("kernel complete timeout") from exc

            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue

            content = msg.get("content", {})
            matches = content.get("matches", [])
            if not isinstance(matches, list):
                matches = []

            start = int(content.get("cursor_start", cursor_pos))
            end = int(content.get("cursor_end", cursor_pos))
            str_matches = [m for m in matches if isinstance(m, str)]
            return str_matches, start, end


class PyreplCompletionLsp:
    def __init__(self, completer: KernelCompleter) -> None:
        self.completer = completer
        self.docs: dict[str, str] = {}
        self.running = True
        self.shutdown_requested = False
        self.exit_code = 0

    def run(self) -> int:
        while self.running:
            msg = read_lsp_message()
            if msg is None:
                break
            self.handle(msg)

        self.completer.close()
        return self.exit_code

    def reply(self, req_id: Any, result: Any) -> None:
        send_lsp_message({"jsonrpc": "2.0", "id": req_id, "result": result})

    def reply_error(
        self, req_id: Any, code: int, message: str, data: Any = None
    ) -> None:
        err: dict[str, Any] = {"code": code, "message": message}
        if data is not None:
            err["data"] = data
        send_lsp_message({"jsonrpc": "2.0", "id": req_id, "error": err})

    def handle(self, msg: dict[str, Any]) -> None:
        has_id = "id" in msg
        req_id = msg.get("id")
        method = msg.get("method")
        params = msg.get("params") or {}

        if not isinstance(method, str):
            if has_id:
                self.reply_error(req_id, -32600, "Invalid Request")
            return

        try:
            result = self.dispatch(method, params)
            if has_id:
                self.reply(req_id, result)
        except LspError as exc:
            if has_id:
                self.reply_error(req_id, exc.code, exc.message, exc.data)
        except Exception as exc:
            if has_id:
                self.reply_error(req_id, -32603, "Internal error", str(exc))
            else:
                log(f"notification error on {method}: {exc!r}")

    def dispatch(self, method: str, params: dict[str, Any]) -> Any:
        if method == "initialize":
            return {
                "capabilities": {
                    "positionEncoding": "utf-16",
                    "textDocumentSync": {"openClose": True, "change": 2, "save": False},
                    "completionProvider": {
                        "resolveProvider": False,
                        "triggerCharacters": ["."],
                    },
                },
                "serverInfo": {"name": "pyrepl-kernel-lsp", "version": "0.1.0"},
            }

        if method == "initialized":
            return None

        if method == "textDocument/didOpen":
            self.did_open(params)
            return None

        if method == "textDocument/didChange":
            self.did_change(params)
            return None

        if method == "textDocument/didClose":
            self.did_close(params)
            return None

        if method == "textDocument/completion":
            return self.completion(params)

        if method == "shutdown":
            self.shutdown_requested = True
            return None

        if method == "exit":
            self.running = False
            self.exit_code = 0 if self.shutdown_requested else 1
            return None

        if method == "$/cancelRequest":
            return None

        raise LspError(-32601, f"Method not found: {method}")

    def did_open(self, params: dict[str, Any]) -> None:
        doc = params.get("textDocument", {})
        uri = doc.get("uri")
        text = doc.get("text")
        if isinstance(uri, str) and isinstance(text, str):
            self.docs[uri] = text

    def did_change(self, params: dict[str, Any]) -> None:
        td = params.get("textDocument", {})
        uri = td.get("uri")
        if not isinstance(uri, str):
            return

        text = self.docs.get(uri, "")

        for change in params.get("contentChanges", []):
            if not isinstance(change, dict):
                continue

            if "range" not in change:
                new_text = change.get("text")
                if isinstance(new_text, str):
                    text = new_text
                continue

            r = change.get("range", {})
            s = r.get("start", {})
            e = r.get("end", {})
            start = position_to_offset(
                text,
                int(s.get("line", 0)),
                int(s.get("character", 0)),
            )
            end = position_to_offset(
                text,
                int(e.get("line", 0)),
                int(e.get("character", 0)),
            )
            if end < start:
                start, end = end, start

            new_text = change.get("text", "")
            if not isinstance(new_text, str):
                new_text = ""
            text = text[:start] + new_text + text[end:]

        self.docs[uri] = text

    def did_close(self, params: dict[str, Any]) -> None:
        td = params.get("textDocument", {})
        uri = td.get("uri")
        if isinstance(uri, str):
            self.docs.pop(uri, None)

    def completion(self, params: dict[str, Any]) -> dict[str, Any]:
        td = params.get("textDocument", {})
        pos = params.get("position", {})

        uri = td.get("uri")
        if not isinstance(uri, str):
            return {"isIncomplete": False, "items": []}

        text = self.docs.get(uri)
        if text is None:
            path = uri_to_path(uri)
            if path is not None:
                try:
                    text = path.read_text(encoding="utf-8")
                except Exception:
                    text = ""
            else:
                text = ""
            self.docs[uri] = text

        line = int(pos.get("line", 0))
        character = int(pos.get("character", 0))
        cursor = position_to_offset(text, line, character)

        try:
            matches, start, end = self.completer.complete(text, cursor)
        except Exception as exc:
            log(f"completion failed: {exc!r}")
            return {"isIncomplete": False, "items": []}

        start = max(0, min(start, len(text)))
        end = max(start, min(end, len(text)))

        edit_range = {
            "start": offset_to_position(text, start),
            "end": offset_to_position(text, end),
        }

        items = []
        seen: set[str] = set()
        for m in matches:
            if m in seen:
                continue
            seen.add(m)
            items.append(
                {
                    "label": m,
                    "kind": 1,
                    "textEdit": {"range": edit_range, "newText": m},
                }
            )

        return {"isIncomplete": False, "items": items}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Minimal LSP server for Jupyter completion")
    p.add_argument(
        "--connection-file", required=True, help="Path to Jupyter connection file"
    )
    p.add_argument(
        "--timeout", type=float, default=0.8, help="Kernel reply timeout (seconds)"
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    try:
        completer = KernelCompleter(args.connection_file, timeout=args.timeout)
    except Exception as exc:
        log(f"failed to connect kernel: {exc!r}")
        return 1

    server = PyreplCompletionLsp(completer)
    return server.run()


if __name__ == "__main__":
    raise SystemExit(main())
