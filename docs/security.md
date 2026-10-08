# Security

Not yet written. **Phase 6** adds OAuth 2.0/OIDC via Microsoft Entra ID,
Gateway API with TLS, Key Vault-sourced secrets, rate limiting, and this
document -- mapping each control to the OWASP Top 10 for LLM Applications
with a link to the implementing code.

## What exists today (Phase 1)

- **LLM01 Prompt Injection**: retrieved document text is isolated from the
  system prompt (never concatenated into it) and citations are
  allow-listed against what was actually retrieved. See
  [services/agent-api/app/graph.py](../services/agent-api/app/graph.py)
  and its tests in
  [services/agent-api/tests/test_prompt_injection.py](../services/agent-api/tests/test_prompt_injection.py).
- Containers run multi-stage builds, slim base images and a non-root user
  (see each service's `Dockerfile`); no secrets are baked into images.
