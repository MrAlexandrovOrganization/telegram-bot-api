include makefiles/versions.mk

DOCKER_COMPOSE_BASE = docker compose --project-directory "$(CURDIR)"
include makefiles/compose.mk
DOCKER_COMPOSE = docker compose --project-directory "$(CURDIR)" $(COMPOSE_FLAGS)

up:
	$(DOCKER_COMPOSE) up -d

down:
	$(DOCKER_COMPOSE) down

logs:
	$(DOCKER_COMPOSE) logs -f

restart:
	$(DOCKER_COMPOSE) restart

.PHONY: up down logs restart

# Read-only validation of every tracked Compose combination, without runtime secrets.
.PHONY: compose-layout-check
compose-layout-check:
	$(DOCKER_COMPOSE_BASE) --env-file /dev/null -f compose/docker-compose.yml --profile '*' config --no-interpolate --no-env-resolution --quiet

check: compose-layout-check

# Russia image lifecycle; legacy Make up keeps its existing contract.
export IMAGE_COMPOSE_FILE := compose/docker-compose.yml:compose/compose.russia.yml
.PHONY: versions image-build image-publish image-deploy image-activate image-check image-compose
versions:
	@printf '%s\n' 'TELEGRAM_BOT_API_IMAGE=$(TELEGRAM_BOT_API_IMAGE)' 'REDSOCKS_VERSION=$(REDSOCKS_VERSION)' 'IPTABLES_VERSION=$(IPTABLES_VERSION)'
image-build:
	python3 scripts/images.py build
image-publish:
	python3 scripts/images.py publish
image-deploy:
	python3 scripts/images.py deploy
image-activate:
	$(IMAGE_COMPOSE) up -d --no-build --pull never --wait --wait-timeout 180
image-check:
	python3 -B scripts/test_images.py
export IMAGE_ARGS
image-compose:
	python3 scripts/images.py compose
include makefiles/ci-deploy.mk

check:
	sh -n scripts/proxy-entrypoint.sh
	$(DOCKER_COMPOSE_BASE) --env-file /dev/null -f compose/docker-compose.yml -f compose/compose.russia.yml config --no-interpolate --no-env-resolution --quiet
