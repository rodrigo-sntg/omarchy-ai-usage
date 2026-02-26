.PHONY: install uninstall lint check help

SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## Install ai-usage to ~/.local/libexec/ai-usage + waybar integration
	@./install.sh

uninstall: ## Uninstall ai-usage and clean up
	@./uninstall.sh

lint: ## Run shellcheck on all scripts
	@echo "Running shellcheck..."
	@shellcheck -x scripts/*.sh && echo "All scripts passed shellcheck ✓"

check: ## Run diagnostic checks (dependencies, credentials, network)
	@bash scripts/ai-usage-check.sh
