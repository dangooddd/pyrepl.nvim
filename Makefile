.PHONY: test test-python test-lua

test: test-python test-lua

test-python:
	python3 -m pytest tests/python

test-lua:
	nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"
