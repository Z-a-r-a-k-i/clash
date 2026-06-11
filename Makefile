.PHONY: help generate lint format test test-resolver-stress export-balance

GODOT ?= godot
OUT ?= res://exports/balance_stats.csv

ifeq ($(OS),Windows_NT)
SHELL := pwsh.exe
.SHELLFLAGS := -NoProfile -Command
# GODOT_HEADLESS redirects APPDATA/LOCALAPPDATA to keep test user data local.
# This avoids polluting system Godot settings and keeps headless runs isolated.
GODOT_HEADLESS = $$godotUserRoot = Join-Path (Get-Location) 'client/.godot-codex-user'; $$env:APPDATA = Join-Path $$godotUserRoot 'AppData'; $$env:LOCALAPPDATA = Join-Path $$godotUserRoot 'LocalAppData'; New-Item -ItemType Directory -Force -Path $$env:APPDATA,$$env:LOCALAPPDATA | Out-Null; & '$(GODOT)' --headless --path client
endif

help:
	@echo "clash - make targets"
	@echo "  generate   Generate code from .proto (only when proto codegen is wired up at M2)"
	@echo "  lint       Lint all stacks (gd, proto)"
	@echo "  format     Format all stacks"
	@echo "  test       Run all tests (server-side tests added at M2)"
	@echo "  test-resolver-stress  Run the resolver stress/performance gate"
	@echo "  export-balance  Export canonical game stats to CSV (OUT=... optional)"

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
ifeq ($(OS),Windows_NT)
	@if (-not (Get-Command '$(GODOT)' -ErrorAction SilentlyContinue)) { Write-Error "Godot executable not found. Run: make test GODOT='C:\path\to\Godot_v4.6.1-stable_mono_win64_console.exe'"; exit 1 }
	@$(GODOT_HEADLESS) --import
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_tile_grid_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_resolver_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_resolver_stress_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_vision_system_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_renderer_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_dev_turn_input_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_dev_play_mode_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_replay_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_network_multiplayer_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_network_live_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_balance_csv_export_headless.gd
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_m0_playtest_smoke_headless.gd
else
	@if ! command -v '$(GODOT)' >/dev/null 2>&1; then echo "Godot executable not found. Run: make test GODOT=/path/to/godot"; exit 1; fi
	@'$(GODOT)' --headless --path client --import
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_tile_grid_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_resolver_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_resolver_stress_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_vision_system_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_renderer_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_dev_turn_input_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_dev_play_mode_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_replay_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_network_multiplayer_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_network_live_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_balance_csv_export_headless.gd
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_m0_playtest_smoke_headless.gd
endif

test-resolver-stress:
ifeq ($(OS),Windows_NT)
	@if (-not (Get-Command '$(GODOT)' -ErrorAction SilentlyContinue)) { Write-Error "Godot executable not found. Run: make test-resolver-stress GODOT='C:\path\to\Godot_v4.6.1-stable_mono_win64_console.exe'"; exit 1 }
	@$(GODOT_HEADLESS) --script scripts/_dev/run_test_resolver_stress_headless.gd
else
	@if ! command -v '$(GODOT)' >/dev/null 2>&1; then echo "Godot executable not found. Run: make test-resolver-stress GODOT=/path/to/godot"; exit 1; fi
	@'$(GODOT)' --headless --path client --script scripts/_dev/run_test_resolver_stress_headless.gd
endif

export-balance:
ifeq ($(OS),Windows_NT)
	@if (-not (Get-Command '$(GODOT)' -ErrorAction SilentlyContinue)) { Write-Error "Godot executable not found. Run: make export-balance GODOT='C:\path\to\Godot_v4.6.1-stable_mono_win64_console.exe'"; exit 1 }
	@$(GODOT_HEADLESS) --script scripts/_dev/export_balance_csv.gd -- '$(OUT)'
else
	@if ! command -v '$(GODOT)' >/dev/null 2>&1; then echo "Godot executable not found. Run: make export-balance GODOT=/path/to/godot"; exit 1; fi
	@'$(GODOT)' --headless --path client --script scripts/_dev/export_balance_csv.gd -- '$(OUT)'
endif
