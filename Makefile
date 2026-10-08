.PHONY: up down logs ps pull-models ingest ask test test-mcp-tools test-agent-api test-ingest-worker clean

COMPOSE := docker compose

up: ## Build and start the full local stack in the background
	$(COMPOSE) up --build -d

down: ## Stop the local stack, keep volumes
	$(COMPOSE) down

logs: ## Tail logs for all services
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

pull-models: ## Pull the Ollama models the services expect (run once after `make up`)
	$(COMPOSE) exec ollama ollama pull qwen2.5:3b
	$(COMPOSE) exec ollama ollama pull nomic-embed-text

ingest: ## Publish every document in data/regulations onto the ingest queue
	python3 scripts/ingest_corpus.py

ask: ## Ask a sample question against the running stack
	curl -s -X POST localhost:8080/ask \
		-H "Content-Type: application/json" \
		-d '{"question": "What does DORA require for ICT incident reporting?"}' | python3 -m json.tool

test: test-mcp-tools test-agent-api test-ingest-worker ## Run unit tests for all three services

test-mcp-tools:
	cd services/mcp-tools && pip install -q -r requirements-dev.txt && pytest -q

test-agent-api:
	cd services/agent-api && pip install -q -r requirements-dev.txt && pytest -q

test-ingest-worker:
	cd services/ingest-worker && pip install -q -r requirements-dev.txt && pytest -q

clean: ## Stop the stack and remove volumes (deletes ingested vectors and pulled models)
	$(COMPOSE) down -v
