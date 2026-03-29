SHELL := /bin/bash

.PHONY: install lint test up down fmt

install:
	python3 -m pip install -r apps/edge-router/requirements.txt -r apps/control-plane/requirements.txt -r apps/worker/requirements.txt -r apps/ai-scheduler/requirements.txt

lint:
	python3 -m py_compile apps/edge-router/main.py apps/control-plane/main.py apps/worker/main.py apps/ai-scheduler/main.py

test:
	python3 -m unittest discover -s tests -p 'test_*.py'

up:
	docker compose -f deploy/docker-compose.yml up -d

down:
	docker compose -f deploy/docker-compose.yml down

fmt:
	@echo "Add black/ruff in your environment for formatting/linting."
