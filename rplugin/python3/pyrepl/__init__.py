import json
import sys
import time
from contextlib import contextmanager
from typing import Any, Iterator, Optional, cast

import pynvim
from jupyter_client.blocking.client import BlockingKernelClient
from jupyter_client.kernelspec import KernelSpecManager, NoSuchKernel
from jupyter_client.manager import KernelManager

sys.dont_write_bytecode = True


@pynvim.plugin
class PyreplPlugin:
    def __init__(self, nvim: pynvim.Nvim):
        """Create the Pyrepl Neovim remote plugin."""
        self.nvim = nvim
        self.kernels: dict[str, KernelManager] = {}
        self.client: Optional[BlockingKernelClient] = None
        self.kernelspec_manager: Optional[KernelSpecManager] = None

    def _disconnect_client(self) -> None:
        """Stop kernel client channels and clear the client."""
        if not self.client:
            return
        try:
            self.client.stop_channels()
        except Exception:
            pass
        self.client = None

    def _get_client(self) -> BlockingKernelClient:
        """Return the active kernel client or raise if missing."""
        if self.client is None:
            raise RuntimeError("Kernel client is not initialized")
        return self.client

    def _get_kernelspec_manager(self) -> KernelSpecManager:
        """Return a cached KernelSpecManager instance."""
        manager = self.kernelspec_manager
        if manager is None:
            manager = KernelSpecManager()
            self.kernelspec_manager = manager
        return manager

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args: list) -> dict[str, Any]:
        """Start a Jupyter kernel and return connection info."""
        if not args:
            return {
                "ok": False,
                "message": "Kernel name is missing.",
            }

        kernel_name = args[0]
        if not isinstance(kernel_name, str) or not kernel_name.strip():
            return {
                "ok": False,
                "message": "Kernel name is missing.",
            }

        kernel_name = kernel_name.strip()
        try:
            kernelspec_manager = self._get_kernelspec_manager()
            try:
                spec = kernelspec_manager.get_kernel_spec(kernel_name)
            except NoSuchKernel:
                return {
                    "ok": False,
                    "message": (
                        f"Kernel '{kernel_name}' not found. "
                        "Install it manually (see README) and try again."
                    ),
                }

            kernel_manager = KernelManager(
                kernel_name=kernel_name,
                kernel_spec_manager=kernelspec_manager,
            )

            # set internal fields so KernelManager starts the exact kernelspec we just resolved
            # and so later consumers see a consistent kernel_name/spec pairing
            manager_any = cast(Any, kernel_manager)
            manager_any.kernel_name = kernel_name
            manager_any._kernel_spec = spec
            kernel_manager.start_kernel()
            self.kernels[kernel_manager.connection_file] = kernel_manager

            return {
                "ok": True,
                "connection_file": kernel_manager.connection_file,
            }

        except Exception as exc:
            self._disconnect_client()
            return {
                "ok": False,
                "message": f"Kernel initialization failed: {type(exc).__name__}: {exc}.",
            }

    @pynvim.function("ListKernels", sync=True)
    def list_kernels(self, args) -> dict[str, Any]:
        """List available Jupyter kernelspecs."""
        try:
            manager = self._get_kernelspec_manager()
            specs = manager.get_all_specs()
            kernels: list[dict[str, str]] = []

            for name, info in specs.items():
                path = ""
                if isinstance(info, dict):
                    spec = info.get("spec") or {}
                    argv = spec.get("argv") or []
                    if argv:
                        # argv[0] is typically the interpreter path used by the kernelspec
                        # lua uses this to prefer a kernel that matches the active venv
                        path = argv[0]
                kernels.append({"name": name, "path": path})

            kernels.sort(key=lambda item: item["name"])
            return {
                "ok": True,
                "value": kernels,
            }

        except Exception as exc:
            return {
                "ok": False,
                "message": f"Failed to list kernels: {exc}",
            }

    def _connect_kernel(self, connection_file: str) -> None:
        """Connect a client to a kernel using a connection file."""
        with open(connection_file, "r", encoding="utf-8") as file_handle:
            connection_info = json.load(file_handle)

        client = BlockingKernelClient()
        client.load_connection_info(connection_info)
        client.start_channels()
        self.client = client

    def _extract_connection_file(self, args: list[Any]) -> Optional[str]:
        """Return the connection file argument if valid."""
        if not args:
            return None
        value = args[0]
        if not isinstance(value, str) or not value:
            return None
        return value

    def _wait_dead_best_effort(
        self,
        client: BlockingKernelClient,
        total_timeout: float = 0.2,
    ) -> None:
        """Wait for kernel shutdown without failing on iopub errors."""
        start_time = time.time()
        while time.time() - start_time < total_timeout:
            try:
                msg = client.get_iopub_msg(timeout=0.5)
            except Exception:
                # best effort only since iopub can stall or disappear during shutdown
                continue
            if (
                msg.get("msg_type") == "status"
                and msg.get("content", {}).get("execution_state") == "dead"
            ):
                return

    @contextmanager
    def _connected_client(self, connection_file: str) -> Iterator[BlockingKernelClient]:
        """Connect a client for a single operation."""
        self._connect_kernel(connection_file)
        try:
            yield self._get_client()
        finally:
            self._disconnect_client()

    @pynvim.function("ShutdownKernel", sync=True)
    def shutdown_kernel(self, args) -> dict[str, Any]:
        """Shut down a Jupyter kernel by connection file."""
        connection_file = self._extract_connection_file(args)
        if not connection_file:
            return {
                "ok": False,
                "message": "Connection file is missing.",
            }

        # self.kernels only tracks kernels started by this plugin instance
        # if the python host was restarted or the kernel was started elsewhere, fall back to a client shutdown
        manager = self.kernels.pop(connection_file, None)
        if manager is not None:
            try:
                manager.shutdown_kernel(now=True)
                return {
                    "ok": True,
                }
            except Exception as exc:
                return {
                    "ok": False,
                    "message": f"Kernel shutdown failed: {exc}",
                }

        try:
            with self._connected_client(connection_file) as client:
                client.shutdown()
                self._wait_dead_best_effort(client, total_timeout=0.2)
            return {
                "ok": True,
            }
        except Exception as exc:
            return {
                "ok": False,
                "message": f"Kernel shutdown failed: {exc}",
            }
