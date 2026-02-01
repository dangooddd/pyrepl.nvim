from __future__ import annotations


def test_init_kernel_missing_args(main_module, dummy_nvim) -> None:
    plugin = main_module.PyreplPlugin(dummy_nvim)
    result = plugin.init_kernel([])

    assert result["ok"] is False
    assert result["error_type"] == "missing_kernel_name"


def test_init_kernel_no_such_kernel(main_module, dummy_nvim) -> None:
    class DummySpecManager:
        def get_kernel_spec(self, _name: str):
            raise main_module.NoSuchKernel("missing")

    plugin = main_module.PyreplPlugin(dummy_nvim)
    plugin._get_kernelspec_manager = lambda: DummySpecManager()

    result = plugin.init_kernel(["missing-kernel"])

    assert result["ok"] is False
    assert result["error_type"] == "no_such_kernel"


def test_init_kernel_success(main_module, dummy_nvim, monkeypatch) -> None:
    class DummySpec:
        argv = ["python3"]

    class DummySpecManager:
        def get_kernel_spec(self, _name: str):
            return DummySpec()

    class DummyClient:
        def __init__(self) -> None:
            self.started = False

        def start_channels(self) -> None:
            self.started = True

    class DummyKernelManager:
        def __init__(self, kernel_name: str, kernel_spec_manager):
            self.kernel_name = kernel_name
            self.kernel_spec_manager = kernel_spec_manager
            self.connection_file = "/tmp/pyrepl.json"
            self.started = False
            self._client = DummyClient()

        def start_kernel(self) -> None:
            self.started = True

        def client(self) -> DummyClient:
            return self._client

    monkeypatch.setattr(main_module, "KernelManager", DummyKernelManager)

    plugin = main_module.PyreplPlugin(dummy_nvim)
    plugin._get_kernelspec_manager = lambda: DummySpecManager()

    result = plugin.init_kernel(["python3"])

    assert result["ok"] is True
    assert result["connection_file"] == "/tmp/pyrepl.json"
    assert plugin.kernel_manager is not None
    assert plugin.client is not None


def test_list_kernels_sorts(main_module, dummy_nvim) -> None:
    class DummySpecManager:
        def get_all_specs(self):
            return {
                "z": {
                    "resource_dir": "/tmp/z",
                    "spec": {"argv": ["python"]},
                },
                "a": {
                    "resource_dir": "/tmp/a",
                    "spec": {"argv": ["python3"]},
                },
            }

    plugin = main_module.PyreplPlugin(dummy_nvim)
    plugin._get_kernelspec_manager = lambda: DummySpecManager()

    kernels = plugin.list_kernels([])

    assert [item["name"] for item in kernels] == ["a", "z"]
    assert kernels[0]["path"] == "/tmp/a"
    assert kernels[1]["argv0"] == "python"


def test_shutdown_kernel_rejects_invalid_args(main_module, dummy_nvim) -> None:
    plugin = main_module.PyreplPlugin(dummy_nvim)

    assert plugin.shutdown_kernel([]) is False
    assert plugin.shutdown_kernel([None]) is False
