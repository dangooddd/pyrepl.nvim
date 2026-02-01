import json
import sys
import time
from typing import Any, Dict, List, Optional, cast

import pynvim
from jupyter_client.blocking.client import BlockingKernelClient
from jupyter_client.kernelspec import KernelSpecManager, NoSuchKernel
from jupyter_client.manager import KernelManager

sys.dont_write_bytecode = True


@pynvim.plugin
class PyreplPlugin:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.kernel_manager: Optional[KernelManager] = None
        self.client: Optional[BlockingKernelClient] = None
        self.kernelspec_manager: Optional[KernelSpecManager] = None

    def _disconnect_client(self) -> None:
        if not self.client:
            return
        try:
            self.client.stop_channels()
        except Exception:
            pass
        self.client = None

    def _get_client(self) -> BlockingKernelClient:
        if self.client is None:
            raise RuntimeError("Kernel client is not initialized")
        return self.client

    def _get_kernelspec_manager(self) -> KernelSpecManager:
        manager = self.kernelspec_manager
        if manager is None:
            manager = KernelSpecManager()
            self.kernelspec_manager = manager
        return manager

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args) -> Dict[str, object]:
        """Initialize Jupyter kernel and return status data."""
        if not args:
            return {
                "ok": False,
                "error_type": "missing_kernel_name",
                "error": "missing kernel name",
            }

        kernel_name = args[0]
        if not isinstance(kernel_name, str) or not kernel_name.strip():
            return {
                "ok": False,
                "error_type": "missing_kernel_name",
                "error": "missing kernel name",
            }
        kernel_name = kernel_name.strip()
        requested_kernel_name = kernel_name
        effective_kernel_name = ""
        spec_argv0 = ""
        try:
            kernelspec_manager = self._get_kernelspec_manager()
            try:
                spec = kernelspec_manager.get_kernel_spec(kernel_name)
            except NoSuchKernel as exc:
                return {
                    "ok": False,
                    "error_type": "no_such_kernel",
                    "error": str(exc),
                    "kernel_name": kernel_name,
                    "requested_kernel_name": requested_kernel_name,
                    "effective_kernel_name": effective_kernel_name,
                }

            if spec and getattr(spec, "argv", None):
                spec_argv0 = spec.argv[0]

            kernel_manager = KernelManager(
                kernel_name=kernel_name,
                kernel_spec_manager=kernelspec_manager,
            )
            manager_any = cast(Any, kernel_manager)
            manager_any.kernel_name = kernel_name
            manager_any._kernel_spec = spec
            effective_kernel_name = kernel_manager.kernel_name
            kernel_manager.start_kernel()
            client = kernel_manager.client()
            client.start_channels()
            self.kernel_manager = kernel_manager
            self.client = client
            return {
                "ok": True,
                "connection_file": kernel_manager.connection_file,
                "kernel_name": kernel_name,
                "requested_kernel_name": requested_kernel_name,
                "effective_kernel_name": effective_kernel_name,
                "spec_argv0": spec_argv0,
            }
        except Exception as exc:
            self._disconnect_client()
            return {
                "ok": False,
                "error_type": "init_failed",
                "error": str(exc),
                "kernel_name": kernel_name,
                "requested_kernel_name": requested_kernel_name,
                "effective_kernel_name": effective_kernel_name,
                "spec_argv0": spec_argv0,
            }

    @pynvim.function("ListKernels", sync=True)
    def list_kernels(self, args) -> List[Dict[str, str]]:
        try:
            manager = self._get_kernelspec_manager()
            specs = manager.get_all_specs()
            kernels: List[Dict[str, str]] = []
            for name, info in specs.items():
                resource_dir = ""
                argv0 = ""
                if isinstance(info, dict):
                    resource_dir = info.get("resource_dir") or ""
                    spec = info.get("spec") or {}
                    argv = spec.get("argv") or []
                    if argv:
                        argv0 = argv[0]
                kernels.append({"name": name, "path": resource_dir, "argv0": argv0})
            kernels.sort(key=lambda item: item.get("name", ""))
            return kernels
        except Exception as exc:
            self.nvim.err_write(f"PyREPL: Failed to list kernels: {exc}\n")
            return []

    def _connect_kernel(self, connection_file: str) -> None:
        """Connect to the Jupyter kernel using the connection file."""
        with open(connection_file, "r", encoding="utf-8") as file_handle:
            connection_info = json.load(file_handle)

        client = BlockingKernelClient()
        client.load_connection_info(connection_info)
        client.start_channels()
        self.client = client

    @pynvim.function("ShutdownKernel", sync=True)
    def shutdown_kernel(self, args) -> bool:
        """Shutdown the Jupyter kernel."""
        if not args:
            return False

        connection_file = args[-1]
        if not isinstance(connection_file, str) or not connection_file:
            return False
        try:
            self._connect_kernel(connection_file)
            client = self._get_client()

            # Send shutdown request
            client.shutdown()

            # Wait for confirmation (optional, but recommended)
            timeout = 0.2
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    msg = client.get_iopub_msg(timeout=0.5)
                    if (
                        msg["msg_type"] == "status"
                        and msg["content"]["execution_state"] == "dead"
                    ):
                        break
                except Exception:
                    pass

            if self.kernel_manager:
                self.kernel_manager.shutdown_kernel(now=True)
                self.kernel_manager = None

            return True
        except Exception as exc:
            self.nvim.err_write(f"Kernel shutdown failed: {exc}\n")
            return False
        finally:
            self._disconnect_client()
