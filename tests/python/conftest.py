from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load module {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class DummyNvim:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def err_write(self, msg: str) -> None:
        self.errors.append(msg)


@pytest.fixture
def dummy_nvim() -> DummyNvim:
    return DummyNvim()


@pytest.fixture
def main_module() -> ModuleType:
    return load_module("pyrepl_main", ROOT / "rplugin/python3/main.py")


@pytest.fixture
def console_module() -> ModuleType:
    return load_module("pyrepl_console", ROOT / "rplugin/python3/console.py")
