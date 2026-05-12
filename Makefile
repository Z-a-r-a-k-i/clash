.PHONY: help generate lint format test

ifeq ($(OS),Windows_NT)
SHELL := pwsh.exe
.SHELLFLAGS := -NoProfile -Command
endif

help:
	@echo "clash — make targets"
	@echo "  generate   Generate code from .proto (only when proto codegen is wired up at M2)"
	@echo "  lint       Lint all stacks (gd, proto)"
	@echo "  format     Format all stacks"
	@echo "  test       Run all tests (server-side tests added at M2)"

generate:
ifeq ($(OS),Windows_NT)
	@if ((Test-Path 'buf.gen.yaml') -or (Get-ChildItem -Path 'proto' -Recurse -Filter '*.proto' -ErrorAction SilentlyContinue | Select-Object -First 1)) { buf generate } else { Write-Output 'no proto files yet; nothing to generate' }
else
	@if [ -f buf.gen.yaml ] || find proto -name '*.proto' 2>/dev/null | grep -q .; then \
		buf generate; \
	else \
		echo "no proto files yet; nothing to generate"; \
	fi
endif

lint:
ifeq ($(OS),Windows_NT)
	@if (Get-ChildItem -Path 'proto' -Recurse -Filter '*.proto' -ErrorAction SilentlyContinue | Select-Object -First 1) { buf lint }
	@$$gdFiles = git ls-files '*.gd'; if ($$gdFiles) { gdlint $$gdFiles }
else
	@if git ls-files '*.proto' | grep -q .; then buf lint; fi
	@if git ls-files '*.gd' | grep -q .; then git ls-files '*.gd' | xargs gdlint; fi
endif

format:
ifeq ($(OS),Windows_NT)
	@if (Get-ChildItem -Path 'proto' -Recurse -Filter '*.proto' -ErrorAction SilentlyContinue | Select-Object -First 1) { buf format -w }
	@$$gdFiles = git ls-files '*.gd'; if ($$gdFiles) { gdformat $$gdFiles }
else
	@if git ls-files '*.proto' | grep -q .; then buf format -w; fi
	@if git ls-files '*.gd' | grep -q .; then git ls-files '*.gd' | xargs gdformat; fi
endif

test:
	@echo "M0 tests are GDScript-based and run inside Godot or via headless --script invocations."
	@echo "Server tests land at M2 alongside the server stack choice (ADR 0006)."
