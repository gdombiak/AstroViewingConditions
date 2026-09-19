PYTHON ?= python3

.PHONY: swift-test python-test parity engine-test

# Resolve a relative PYTHON (e.g. packages/.../.venv/bin/python) against the
# repo root so targets can cd into packages without breaking the path.
define python_cmd
case "$(PYTHON)" in \
  /*) py="$(PYTHON)" ;; \
  */*) py="$(CURDIR)/$(PYTHON)" ;; \
  *) py="$(PYTHON)" ;; \
esac
endef

swift-test:
	swift test --package-path packages/astro-engine-swift

python-test:
	cd packages/astro-engine-python && $(python_cmd); "$$py" -m pytest

parity:
	$(python_cmd); PYTHON="$$py" scripts/parity

engine-test: swift-test python-test parity
