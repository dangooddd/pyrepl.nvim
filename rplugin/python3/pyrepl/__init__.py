from functools import lru_cache
from typing import Any, Optional, cast

import pynvim
from jupyter_client.kernelspec import KernelSpecManager

PREFERRED_KERNEL = "python3"


@lru_cache
def kernelspec_manager() -> KernelSpecManager:
    """Return cached kernelspec manager."""
    return KernelSpecManager()


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
            {"name": name, "resource_dir": spec["resource_dir"]}
            for name, spec in specs.items()
        ]
        kernels.sort(key=lambda v: v["name"] != PREFERRED_KERNEL)
        return kernels
