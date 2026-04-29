.PHONY: help generate lint format test

help:
	@echo "clash — make targets"
	@echo "  generate   Generate code from .proto (only when proto codegen is wired up at M2)"
	@echo "  lint       Lint all stacks (gd, proto)"
	@echo "  format     Format all stacks"
	@echo "  test       Run all tests (server-side tests added at M2)"

generate:
	@if [ -f buf.gen.yaml ] || find proto -name '*.proto' 2>/dev/null | grep -q .; then \
		buf generate; \
	else \
		echo "no proto files yet; nothing to generate"; \
	fi

lint:
	@if find proto -name '*.proto' 2>/dev/null | grep -q .; then buf lint; fi
	@if find client -name '*.gd' 2>/dev/null | grep -q .; then gdlint client; fi

format:
	@if find proto -name '*.proto' 2>/dev/null | grep -q .; then buf format -w; fi
	@if find client -name '*.gd' 2>/dev/null | grep -q .; then gdformat client; fi

test:
	@echo "M0 tests are GDScript-based and run inside Godot or via headless --script invocations."
	@echo "Server tests land at M2 alongside the server stack choice (ADR 0006)."
