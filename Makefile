.PHONY: test test-python test-lua lint lint-ruff lint-ty

test: test-python test-lua

lint: lint-ruff lint-ty

test-python:
	python3 -m pytest tests/python

test-lua:
	nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"

lint-ruff:
	python3 -m ruff check .

lint-ty:
	python3 -m ty check
