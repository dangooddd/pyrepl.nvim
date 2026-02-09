.PHONY: lint lint-ruff lint-ty

lint: lint-ruff lint-ty

lint-ruff:
	ruff check

lint-ty:
	ty check
