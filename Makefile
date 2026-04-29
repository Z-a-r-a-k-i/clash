.PHONY: help generate lint format test

help:
	@echo "clash — make targets"
	@echo "  generate   Generate code from .proto (buf generate)"
	@echo "  lint       Lint all stacks (cs, gd, go, proto)"
	@echo "  format     Format all stacks"
	@echo "  test       Run all tests"

generate:
	@if [ -f buf.gen.yaml ] || find proto -name '*.proto' 2>/dev/null | grep -q .; then \
		buf generate; \
	else \
		echo "no proto files yet; nothing to generate"; \
	fi

lint:
	@if find proto -name '*.proto' 2>/dev/null | grep -q .; then buf lint; fi
	@if find client -name '*.gd' 2>/dev/null | grep -q .; then gdlint client; fi
	@if [ -f client/Clash.sln ] || ls client/*.csproj 2>/dev/null | grep -q .; then \
		cd client && dotnet format --verify-no-changes; \
	fi
	@if [ -f server/go.mod ]; then cd server && go vet ./...; fi

format:
	@if find proto -name '*.proto' 2>/dev/null | grep -q .; then buf format -w; fi
	@if find client -name '*.gd' 2>/dev/null | grep -q .; then gdformat client; fi
	@if [ -f client/Clash.sln ] || ls client/*.csproj 2>/dev/null | grep -q .; then \
		cd client && dotnet format; \
	fi
	@if [ -f server/go.mod ]; then cd server && golangci-lint fmt; fi

test:
	@if [ -f client/Clash.sln ] || ls client/*.csproj 2>/dev/null | grep -q .; then \
		cd client && dotnet test --nologo; \
	fi
	@if [ -f server/go.mod ]; then cd server && go test -race ./...; fi
