import os
from functools import lru_cache
from pathlib import Path
from typing import Any, cast

import pynvim
from jupyter_client.kernelspec import KernelSpecManager

VENV_ENV_VARS = [
    "VIRTUAL_ENV",
    "CONDA_PREFIX",
]


@lru_cache
def kernelspec_manager() -> KernelSpecManager:
    """Return cached kernelspec manager."""
    return KernelSpecManager()


@lru_cache()
def get_venv():
    for venv in VENV_ENV_VARS:
        if os.environ.get(venv) is not None:
            return str(Path(os.environ[venv]) / "bin" / "python")

    return None


def is_relative(target: str | Path, base: str | Path):
    target = Path(target).resolve()
    base = Path(base).resolve()
    return base in target.parents or base == target


@pynvim.plugin
class PyreplPlugin:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim

    @pynvim.function("PyreplListKernels", sync=True)
    def list_kernels(self, _):
        """List available Jupyter kernelspecs."""
        manager = kernelspec_manager()
        specs = cast(dict[str, dict[str, Any]], manager.get_all_specs())

        kernels = [
            {
                "name": name,
                "resource_dir": spec["resource_dir"],
                "python_path": spec["spec"]["argv"][0],
            }
            for name, spec in specs.items()
        ]

        venv = get_venv()
        if venv is not None:
            key = lambda item: is_relative(item["python_path"], venv)
            kernels.sort(key=key, reverse=True)

        return kernels
