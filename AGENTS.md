# Agent Contract — Zammad-MCP

This document defines how automated coding agents (and humans using them) should work in this repository.

## Scope

- This repo provides a Model Context Protocol (MCP) server for the Zammad ticket system.
- It exposes tools/resources/prompts via FastMCP and wraps the Zammad HTTP API.
- Optional PII anonymization can be enabled via the `pii` extra (powered by `llm-anon-core`).

## Responsibility boundary

- This repo owns:
  - MCP surface area (tools/resources/prompts), response formatting, and truncation.
  - Zammad API integration/wrappers, parameter validation (Pydantic), and error formatting.
  - Host-side safeguards (e.g. path validation for attachment read/write).
- `llm-anon-core` owns:
  - Anonymization/de-anonymization primitives, vault semantics, Presidio/spaCy setup, and token restoration.
- If a change affects anonymization behavior, prefer implementing it upstream in `llm-anon-core` first, then updating the pinned revision here.

## Golden rules

- Do not log, persist, or commit raw PII in code changes, tests, fixtures, or docs.
- Prefer small, reviewable changes; avoid drive-by refactors.
- Keep changes runnable; if behavior changes, add/adjust tests.
- Treat operator-facing docs as part of the API: update docs in the same change when you change behavior/config.
- Do not introduce new services/background processes unless explicitly requested.

## Documentation sources of truth

Treat these as the authoritative user/operator interface:

- `README.md`
- `ARCHITECTURE.md`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `CLAUDE.md` (developer/agent guidance and commands)

If you change configuration, behavior, endpoints, or workflows, update the relevant docs in the same PR.

## Repository layout

- `mcp_zammad/server.py`: FastMCP server definition (tools/resources/prompts) and server-side utilities.
- `mcp_zammad/client.py`: Zammad API wrapper and higher-level helper methods.
- `mcp_zammad/models.py`: Pydantic models and validators.
- `mcp_zammad/pii_client.py`: Optional PII filtering integration.
- `tests/`: unit/integration-style tests (mock Zammad API/client).
- `scripts/`: setup, quality checks, CI helpers.

## Dependency management (`uv`)

- This project uses `uv`.
- `uv.lock` is expected to be committed when dependency resolution changes.
- Avoid regenerating `uv.lock` unless you are intentionally changing dependencies.

Common commands (repo root):

```bash
uv sync --extra dev
uv run pytest
uv run ruff format mcp_zammad tests
uv run ruff check mcp_zammad tests
uv run mypy mcp_zammad
```

## Optional PII anonymization (`llm-anon-core`)

- PII support is optional and enabled by installing the `pii` extra:

```bash
uv sync --extra pii
```

- The dependency is sourced via `pyproject.toml`:

```toml
[project.optional-dependencies]
pii = ["llm-anon-core"]

[tool.uv.sources]
llm-anon-core = { git = "https://git.b.picoquant.com/ruettinger/llm-anon-core.git" }
# or (local development)
# llm-anon-core = { path = "vendor/llm-anon-core", editable = true }
```

Guidelines:

- Prefer updating the pinned upstream revision (lockfile) over editing vendored code.
- If you use the vendored copy for local dev, keep it aligned with upstream and avoid committing large unrelated upstream diffs.
- When updating `llm-anon-core`, ensure `uv.lock` reflects the new git commit and commit the lockfile change.

## Security invariants

- Do not broaden filesystem access: host file reads/writes must remain constrained by configured roots (e.g. `KB_UPLOAD_ROOT`, `KB_DOWNLOAD_ROOT`).
- Do not remove response-size safeguards (`truncate_response`) on tool/resource outputs.
- Errors should remain consistent with existing project patterns (error formatting helpers, stable messages for tests).

## Testing and change safety

Before submitting changes:

- Tests pass (`uv run pytest`).
- Any behavior change includes tests (or a brief justification if infeasible).
- No secrets committed (tokens, credentials, `.env` content).
- Any `uv.lock` changes are intentional and explained.
