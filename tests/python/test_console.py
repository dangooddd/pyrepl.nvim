from __future__ import annotations


def test_extract_image_data(console_module) -> None:
    extract = console_module._extract_image_data

    assert extract("abc") == "abc"
    assert extract(b"abc") == "abc"
    assert extract(["a", "b"]) == "ab"
    assert extract([b"a", b"b"]) == "ab"
    assert extract([["z"]]) == "z"
    assert extract([]) == ""


def test_read_env_int(console_module, monkeypatch) -> None:
    read_int = console_module._read_env_int
    key = "PYREPL_TEST_INT"

    monkeypatch.delenv(key, raising=False)
    assert read_int(key, 10) == 10

    monkeypatch.setenv(key, "12")
    assert read_int(key, 10) == 12

    monkeypatch.setenv(key, "0")
    assert read_int(key, 10) == 10

    monkeypatch.setenv(key, "bad")
    assert read_int(key, 10) == 10


def test_read_env_float(console_module, monkeypatch) -> None:
    read_float = console_module._read_env_float
    key = "PYREPL_TEST_FLOAT"

    monkeypatch.delenv(key, raising=False)
    assert read_float(key, 0.5) == 0.5

    monkeypatch.setenv(key, "0.25")
    assert read_float(key, 0.5) == 0.25

    monkeypatch.setenv(key, "0")
    assert read_float(key, 0.5) == 0.5

    monkeypatch.setenv(key, "2.5")
    assert read_float(key, 0.5) == 1.0

    monkeypatch.setenv(key, "bad")
    assert read_float(key, 0.5) == 0.5


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
