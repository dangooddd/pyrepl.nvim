.PHONY: lint lint-ruff lint-ty

lint: lint-ruff lint-ty

lint-ruff:
	python3 -m ruff check .

lint-ty:
	python3 -m ty check
