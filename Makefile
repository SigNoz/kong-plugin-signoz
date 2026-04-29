ROCKSPEC := $(wildcard kong-plugin-signoz-*.rockspec)

.PHONY: help install pack upload clean up down restart

help:
	@echo "Targets:"
	@echo "  install     luarocks make — installs into the local tree"
	@echo "  pack        luarocks pack — emits a .src.rock"
	@echo "  upload      luarocks upload (LUAROCKS_API_KEY required)"
	@echo "  clean       Remove .rock artefacts"
	@echo "  up          Start docs/examples/ docker compose"
	@echo "  down        Stop docs/examples/ docker compose"

install:
	luarocks make $(ROCKSPEC)

pack:
	luarocks pack $(ROCKSPEC)

upload:
	@if [ -z "$$LUAROCKS_API_KEY" ]; then \
		echo "LUAROCKS_API_KEY env var required"; exit 1; \
	fi
	luarocks upload $(ROCKSPEC) --api-key=$$LUAROCKS_API_KEY

clean:
	rm -f *.rock

up:
	cd docs/examples && docker compose up -d

down:
	cd docs/examples && docker compose down
