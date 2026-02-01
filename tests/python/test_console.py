from __future__ import annotations


def test_extract_image_data(console_module) -> None:
    extract = console_module._extract_image_data

    assert extract("abc") == "abc"
    assert extract(b"abc") == "abc"
    assert extract(["a", "b"]) == "ab"
    assert extract([b"a", b"b"]) == "ab"
    assert extract([["z"]]) == "z"
    assert extract([]) == ""


def test_disconnect_detection(console_module) -> None:
    interpreter = console_module.ReplInterpreter.__new__(console_module.ReplInterpreter)

    assert interpreter._is_nvim_disconnect_error(BrokenPipeError()) is True
    assert interpreter._is_nvim_disconnect_error(EOFError()) is True
    assert interpreter._is_nvim_disconnect_error(Exception("socket closed")) is True
    assert interpreter._is_nvim_disconnect_error(Exception("other")) is False


def test_handle_disconnect_clears_nvim(console_module) -> None:
    interpreter = console_module.ReplInterpreter.__new__(console_module.ReplInterpreter)
    interpreter.nvim = object()
    interpreter._image_debug = False

    assert interpreter._handle_nvim_disconnect(BrokenPipeError(), "context") is True
    assert interpreter.nvim is None


def test_vim_escape_string(console_module) -> None:
    interpreter = console_module.ReplInterpreter.__new__(console_module.ReplInterpreter)

    assert interpreter._vim_escape_string('a"b\\c') == 'a\\"b\\\\c'
