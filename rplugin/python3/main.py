import sys

sys.dont_write_bytecode = True

import json
import time
from typing import Optional

import pynvim
from jupyter_client import BlockingKernelClient, KernelManager


@pynvim.plugin
class PyrolaPlugin:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.kernel_manager: Optional[KernelManager] = None
        self.client: Optional[BlockingKernelClient] = None

    def _disconnect_client(self) -> None:
        if not self.client:
            return
        try:
            self.client.stop_channels()
        except Exception:
            pass
        self.client = None

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args) -> Optional[str]:
        """Initialize Jupyter kernel and return connection file path."""
        if not args:
            self.nvim.err_write("Pyrola: missing kernel name\n")
            return None

        kernel_name = args[0]
        try:
            self.kernel_manager = KernelManager(kernel_name=kernel_name)
            self.kernel_manager.start_kernel()
            self.client = self.kernel_manager.client()
            self.client.start_channels()
            return self.kernel_manager.connection_file
        except Exception as exc:
            self.nvim.err_write(f"Kernel initialization failed: {exc}\n")
            self._disconnect_client()
            return None

    def _connect_kernel(self, connection_file: str) -> bool:
        """Connect to the Jupyter kernel using the connection file."""
        try:
            with open(connection_file, "r", encoding="utf-8") as file_handle:
                connection_info = json.load(file_handle)

            self.client = BlockingKernelClient()
            self.client.load_connection_info(connection_info)
            self.client.start_channels()
            return True
        except Exception as exc:
            print(f"Connection error: {exc}")
            self._disconnect_client()
            return False

    @pynvim.function("ShutdownKernel", sync=True)
    def shutdown_kernel(self, args) -> bool:
        """Shutdown the Jupyter kernel."""
        if len(args) < 2:
            return False

        _, connection_file = args
        try:
            if not self._connect_kernel(connection_file):
                return False

            # Send shutdown request
            self.client.shutdown()

            # Wait for confirmation (optional, but recommended)
            timeout = 0.2
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    msg = self.client.get_iopub_msg(timeout=0.5)
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
