import json
import sys
import time
from typing import Optional

import pynvim
from jupyter_client.blocking.client import BlockingKernelClient
from jupyter_client.manager import KernelManager

sys.dont_write_bytecode = True


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

    def _get_client(self) -> BlockingKernelClient:
        if self.client is None:
            raise RuntimeError("Kernel client is not initialized")
        return self.client

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args) -> Optional[str]:
        """Initialize Jupyter kernel and return connection file path."""
        if not args:
            self.nvim.err_write("Pyrola: missing kernel name\n")
            return None

        kernel_name = args[0]
        try:
            kernel_manager = KernelManager(kernel_name=kernel_name)
            kernel_manager.start_kernel()
            client = kernel_manager.client()
            client.start_channels()
            self.kernel_manager = kernel_manager
            self.client = client
            return kernel_manager.connection_file
        except Exception as exc:
            self.nvim.err_write(f"Kernel initialization failed: {exc}\n")
            self._disconnect_client()
            return None

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
        if len(args) < 2:
            return False

        _, connection_file = args
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
