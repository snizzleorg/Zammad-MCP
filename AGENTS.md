# Agent Contract — Zammad-MCP

This document defines how automated coding agents (and humans using them) should work in this
repository. `CLAUDE.md` is a symlink to this file — Claude Code and other agent tooling read the
same content here.

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
- `AGENTS.md` (this file — developer/agent guidance and commands; `CLAUDE.md` symlinks here)

If you change configuration, behavior, endpoints, or workflows, update the relevant docs in the same PR.

## Repository layout

- `mcp_zammad/server.py`: FastMCP server definition (tools/resources/prompts) and server-side utilities.
- `mcp_zammad/client.py`: Zammad API wrapper and higher-level helper methods.
- `mcp_zammad/models.py`: Pydantic models and validators.
- `mcp_zammad/pii_client.py`: Optional PII filtering integration.
- `tests/`: unit/integration-style tests (mock Zammad API/client).
- `scripts/`: setup, quality checks, CI helpers.

## Quick Reference Commands

```bash
# Environment setup
mise run setup                    # Complete dev environment setup

# Testing
uv run pytest                     # Run tests
uv run pytest --cov=mcp_zammad   # Run with coverage

# Code quality
uv run ruff format mcp_zammad tests  # Format code
uv run ruff check mcp_zammad tests   # Lint
uv run mypy mcp_zammad              # Type check
./scripts/quality-check.sh          # Run all checks (mutating: applies fixes, writes reports)

# Changelog management
mise run changelog                # Update unreleased section
mise run changelog-bump <version> # Prepare release
```

## Development Rules

**ALWAYS:**

- Use `rg` instead of `grep`
- Use `mise run changelog` to update CHANGELOG.md
- Run quality checks before committing
- Mock `ZammadClient` in tests
- Use Python 3.10+ type syntax: `list[str]` not `List[str]`
- Use modern union syntax: `str | None` not `Optional[str]`

**NEVER:**

- Use bare `grep` command
- Manually edit CHANGELOG.md released sections
- Commit without running pre-commit hooks
- Use deprecated typing module imports

## Dependency management (`uv`)

- This project uses `uv`.
- `uv.lock` is expected to be committed when dependency resolution changes.
- Avoid regenerating `uv.lock` unless you are intentionally changing dependencies.

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

## Architecture

**Project Type:** Model Context Protocol (MCP) server for Zammad ticket system

**FastMCP Version:** 3.x (standalone `fastmcp` package)

**Core Files:**

- `mcp_zammad/server.py` - FastMCP server with 45 tools, 7 resources, 3 prompts
- `mcp_zammad/client.py` - Zammad API wrapper with authentication & validation
- `mcp_zammad/models.py` - Pydantic models for type safety
- `mcp_zammad/pii_client.py` - Optional PII filtering integration

**Response Formats:**

All data-returning tools support two output formats:

- **Markdown** (default): Human-readable text optimized for LLM consumption
- **JSON**: Complete structured data with all metadata fields

This unification follows MCP best practices for consistent tool output.

**Key Patterns:**

- Dependency injection for client sharing
- Sentinel pattern (`_UNINITIALIZED`) for type safety
- Type narrowing with `get_zammad_client()` helper
- Async-first architecture

## FastMCP contract (do NOT revert)

- Import `FastMCP` from `fastmcp`, not `mcp.server.fastmcp`.
- `FastMCP()` does NOT accept `host`/`port`; pass them to `mcp.run(transport="http", host=..., port=...)`.
- Supported transports are `stdio` (default), `http`, and `sse`. HTTP/SSE require `MCP_PORT`; `MCP_HOST` defaults to `127.0.0.1`.
- HTTP transport name is `"http"` (not `"streamable-http"`).
- `ToolAnnotations` is still imported from `mcp.types`; keep tool annotations accurate — distinguish read-only, write, idempotent-write, and destructive operations.
- In tests, use `await mcp.get_tool(name)` (not `mcp._tool_manager._tools`).
- Register tools, resources, and prompts through the `ZammadMCPServer` setup methods. Test observable MCP behavior through public FastMCP or process boundaries; do not add new assertions against private registries.

## Environment Configuration

Required environment variables (see `.env.example`):

```bash
ZAMMAD_URL=https://instance.zammad.com/api/v1  # Must include /api/v1
ZAMMAD_HTTP_TOKEN=your-api-token                # Recommended auth method
```

- Authentication also supports OAuth2 token or username/password. Secret-file variants are supported for token and password inputs; see `.env.example` and `mcp_zammad/client.py`.
- TLS verification is enabled by default. `ZAMMAD_INSECURE` is an explicit escape hatch for trusted self-signed environments and must not become a silent default.

## Testing Standards

**Coverage Target:** 90%+ (current: 90.08%; CI's automated gate-check message reports against an 86% threshold — treat 90%+ as the real bar for new code)

**Test Organization:**

1. Fixtures at top
1. Basic tests
1. Parametrized tests
1. Error cases

**Requirements:**

- Always mock `ZammadClient` and external dependencies
- Use factory fixtures for test data
- Test validation errors and unhappy paths
- Ensure backward compatibility with wrapper functions

## Code Standards

**Tooling:**

- Ruff (format + lint, 120 char line length)
- MyPy (strict type checking)
- Python 3.10+ required (currently pinned to 3.13)

**Type Annotations:**

```python
# DO
list[str]
str | None
cast(ZammadClient, client)

# DON'T
List[str]
Optional[str]
```

**Naming:**

- Avoid parameter shadowing: use `article_type` not `type`

## Adding New Features

**MCP Components:**

- Tools: Add to `server.py` with `@mcp.tool()` decorator
- Resources: Add handlers in `server.py` (URI: `zammad://entity/id`)
- Prompts: Use `@mcp.prompt()` decorator

**Data Flow:**

1. Define Pydantic model in `models.py`
1. Add client method in `client.py`
1. Create MCP tool in `server.py`
1. Add tests with mocked client

## Security

**Implemented:**

- URL validation (SSRF protection)
- HTML sanitization (XSS protection)
- Input validation via Pydantic
- Base64 validation for attachments
- Filename sanitization (path traversal prevention)

**Not Implemented:**

- Rate limiting
- Audit logging

**Invariants:**

- Do not broaden filesystem access: host file reads/writes must remain constrained by configured roots (e.g. `KB_UPLOAD_ROOT`, `KB_DOWNLOAD_ROOT`).
- Do not remove response-size safeguards (`truncate_response`) on tool/resource outputs.
- Errors should remain consistent with existing project patterns (error formatting helpers, stable messages for tests).
- Never place real Zammad credentials in tests, fixtures, logs, examples, or committed environment files.

## Testing and change safety

Before submitting changes:

- Tests pass (`uv run pytest`).
- Any behavior change includes tests (or a brief justification if infeasible).
- No secrets committed (tokens, credentials, `.env` content).
- Any `uv.lock` changes are intentional and explained.

## Additional Information

- **Deployment**: See README.md
- **API Documentation**: See docstrings in source files
- **Known Issues**: See GitHub Issues
- **Changelog**: See CHANGELOG.md (managed by git-cliff)

---

## Appendix: inherited automation/TDD contract

The section below is carried over verbatim from upstream (`basher83/Zammad-MCP`)'s `AGENTS.md` as
part of syncing this fork. It's a generic operating-contract template upstream composes into their
repos from shared "blocks", not something written specifically for this fork. Some of it (e.g. the
strict TDD RED→GREEN→REFACTOR gate on all production code, and the automation-bootstrap
requirements) is more prescriptive than this fork's current day-to-day practice described above.
Treat it as upstream's standard rather than an accurate description of how this repo is actually
developed today, and reconcile the two if you rely on it.

<!-- block: core/blocks/automation.md -->

# Automation foundation

Bootstrap, performance, and CI/CD discipline for code-modifying work. Compose this block into
code-oriented modes ahead of the TDD contract. This is the de-interwoven source of the original
operating contract's automation sections (Definitions + bootstrap + performance + CI/CD).

## Definitions

- **Production code**: application, library, service, or runtime code that changes shipped system behavior.
- **Current scope**: the repo's currently real behavior, boundaries, build surfaces, packaging/release surfaces, and applicable validation needs. Do not invent future scope.
- **Local CI/CD configuration**: the local developer validation suite, the local release-readiness validation suite, and the canonical shared rules/scripts/configuration that drive them.
- **Automation foundation**: all of the following for the current scope:
  1. one canonical source of gates, rules, and failure conditions
  1. a local developer validation suite
  1. a local release-readiness validation suite
  1. changed-file / affected-target execution, or a safe documented fallback
  1. deterministic caching, or a safe documented deterministic no-cache fallback
  1. safe parallel execution where applicable
  1. a matching minimal GitHub Agentic Workflow
  1. verified local ↔ GitHub parity for the current scope
- Tests, validation scripts, CI/CD config, and bootstrap automation may be created before production code when required by this contract.


## Mandatory minimal automation bootstrap

Before writing any production test or any production code, you MUST establish and validate a **minimal automation foundation** for the current scope.

This bootstrap is mandatory.

It is not realistic to have all CI/CD perfect at the start. Therefore:

- perfection is **not** required before RED
- a minimal, deterministic, safe, working automation foundation **is** required before RED
- that foundation must pass for the current scope
- that foundation must evolve in lockstep as production tests, production code, boundaries, build surfaces, packaging, and release concerns evolve
- no new production capability may permanently outrun the automation required to validate it safely

### Bootstrap requirements

Before RED begins, create and validate the currently applicable versions of:

- a local developer validation suite for fast feedback
- a local release-readiness validation suite sized to the current scope
- changed-file / affected-target execution, or an explicitly documented safe fallback
- deterministic caching, or an explicitly documented deterministic no-cache fallback
- safe parallel execution where applicable
- a matching minimal GitHub Agentic Workflow
- one canonical source of format, lint, type, structure, test, cache, affected-target, build, release, and failure rules

These may begin minimal, but they MUST exist before any production tests are written, and they MUST evolve with the system.

### Bootstrap objectives

For the current scope, automation MUST provide:

- immediate feedback
- localized failures
- incremental execution where correctness permits
- avoidance of re-running unaffected work where correctness permits
- deterministic gates
- local and GitHub results that match as closely as environments allow
- minimal, safe, reproducible, fast execution

### Local developer validation suite

Before any production tests are written, a minimal local developer validation suite MUST exist and include every cheap, deterministic, currently applicable developer-feedback gate, including where applicable:

- format validation
- linting
- type checking
- unit and integration test execution
- build verification
- structure-rule enforcement
- changed-file / impacted-target filtering
- fast-fail behavior
- watch mode

It MUST be optimized for feedback:

- sub-second to a few seconds for small edits when feasible
- incremental by default
- parallel where safe
- no unnecessary full-repo scans
- no unnecessary full test runs
- no nondeterministic steps

As production tests and production code evolve, this suite MUST evolve too.

### Local release-readiness validation suite

Before any production tests are written, an initial local release-readiness validation suite MUST also exist.

It validates release and deployment readiness for the **current known release surface** and expands as the system evolves. Where applicable, it includes:

- full-repo validation
- artifact buildability
- packaging correctness
- configuration validation
- environment contract validation
- deployment preflight checks
- rollback readiness validation

It MUST be deterministic and reproducible, must not depend on hidden machine state, may be slower than the developer suite, and must be runnable on demand and before release/promotion.

### Canonical gate definition

All gates MUST be defined once and reused wherever technically possible.

The canonical source MUST govern:

- format rules
- lint rules
- type rules
- structural limits
- test policies
- cache behavior
- affected-target logic
- build validation rules
- release validation rules
- failure conditions

Local and GitHub automation must consume or derive from the same canonical source. No duplicated logic that can drift unless technically unavoidable; any unavoidable duplication must be documented and minimized.

Every new gate or rule change MUST be added to the canonical source first.

### Matching GitHub Agentic Workflow

Before any production tests are written, you MUST create a minimal GitHub Agentic Workflow that mirrors the current local validation model as closely as possible.

It MUST:

- mirror current local gates
- preserve the same pass/fail semantics for equivalent inputs
- run checks in parallel where possible
- fast-fail on critical failures where supported
- avoid re-running unaffected work where correctness permits
- remain deterministic
- use minimal permissions
- isolate agent analysis from write operations

It may start minimal, but it MUST evolve with the system.

### GitHub Agentic Workflow safety model

The GitHub workflow MUST ensure:

- agent execution is isolated
- agent execution is read-only by default
- proposed actions are emitted as structured outputs or artifacts
- any write is performed only by a separate, explicitly scoped, guarded job
- suspicious, malformed, or unsafe outputs fail the workflow
- secrets are not exposed to the agent unless strictly required for a narrowly scoped step
- network access is minimized and explicitly controlled where possible

The agent may analyze, reason, and propose. It must not directly mutate the repository, create uncontrolled side effects, or bypass guarded write steps.

### Local ↔ GitHub parity

For every local gate that exists, there MUST be a corresponding GitHub gate unless the gate is inherently local-only.

Parity includes, where applicable:

- formatter behavior
- linter behavior
- type-checker behavior
- structure-rule behavior
- test selection behavior
- full-suite behavior
- build verification behavior
- release-readiness behavior
- failure semantics
- cache semantics where feasible

Any divergence is a defect unless explicitly unavoidable due to environment differences. Any unavoidable divergence MUST be documented and minimized.

### Bootstrap order

Before writing production tests:

1. define canonical rules and failure conditions for the current scope
1. set up the local developer validation suite
1. set up the local release-readiness validation suite
1. set up affected-target execution or a safe documented fallback
1. set up deterministic caching or a safe deterministic no-cache fallback
1. set up safe parallel execution
1. set up the matching minimal GitHub Agentic Workflow
1. verify local ↔ GitHub parity for the current scope
1. only then begin RED

### Bootstrap verification

RED may begin only when, for the current scope:

- the automation foundation exists
- the local developer suite passes
- the local release-readiness suite passes
- changed-file / affected-target execution works, or the documented safe fallback works
- full validation works
- caches work where enabled, or deterministic no-cache behavior is confirmed where caching is deferred
- enabled parallel execution works correctly
- the GitHub workflow reflects the currently implemented gates and failure conditions
- local and GitHub outcomes match for equivalent inputs as closely as environments allow

### Ongoing evolution

Bootstrap is not a one-time event.

A minimal local CI/CD configuration and matching minimal GitHub Agentic Workflow MUST exist before any production tests are written, and they MUST evolve as production tests and production code evolve.

## Performance mandate

All engineering activity MUST maximize speed without sacrificing determinism, safety, correctness, or TDD constraints.

**Core principle:** any unnecessary slowdown is a defect.

If two approaches are equally correct, choose the faster one.

### Speed requirements

Automation, builds, tests, linting, type checking, feedback loops, local validation, release-readiness validation, and GitHub workflows MUST be as fast as possible while remaining correct and deterministic.

Required properties:

- incrementality where possible
- safe parallelism where possible
- determinism and cacheability where possible
- no hidden global state that breaks caching or parallelism
- no blocking of unrelated work without cause
- no duplicated automation logic that can be shared
- local feedback in sub-second to a few seconds for small edits when feasible
- CI feedback accelerated via parallelism, impact analysis, and fast-fail

Specific expectations:

- builds: incremental by default, avoid full rebuilds unless necessary, use caching, minimize I/O/bundling/transformations
- tests: hermetic, isolated, parallel where safe, support impact analysis where correct, avoid slow setup/teardown and unnecessary integration scope in unit tests
- lint/typecheck: incremental and watch mode where supported, process only changed or affected inputs when correct, avoid redundant passes, parallelize where supported

### Prohibited performance anti-patterns

- starting production TDD before the current-scope automation foundation exists
- running the full test suite on every change when not required for correctness
- global cache invalidation without cause
- sequential execution where safe parallelism is possible
- recomputing unchanged artifacts
- tests depending on shared mutable state
- long-running setup inside individual tests
- reprocessing unchanged inputs without cause
- CI pipelines serializing independent jobs
- local and GitHub pipelines drifting in behavior
- remote workflows re-running work that can be safely skipped based on trusted prior validation and equivalent inputs

### Required optimization strategies

- test impact analysis
- incremental compilation and type checking
- persistent caching across runs
- parallel execution for tests, linting, type checking, builds, and validation jobs where safe
- watch mode where applicable
- deterministic precomputation and memoization
- fast-fail mechanisms
- canonical shared gate definitions
- local-first validation before remote execution

### Enforcement

- performance regressions are failures
- speed improvements are part of REFACTOR
- any noticeable slowdown must be investigated and resolved
- automation parity regressions are failures


## Automation and CI/CD constraints

- A minimal local developer validation suite is mandatory before any production tests.
- An initial local release-readiness validation suite is mandatory before any production tests.
- A matching minimal GitHub Agentic Workflow is mandatory before any production tests.
- All three must remain aligned for the current scope.
- All three must evolve as production tests and production code evolve.
- Any gate change MUST update the canonical source first.
- No local-only or GitHub-only standards unless explicitly justified and documented.
- Agent execution has no write privileges by default.
- No unguarded remote side effects.
- No unnecessary secret exposure to agent execution.
- No bypass of guarded write jobs.


## Required working style

When implementing:

- first determine whether the automation foundation exists and passes for the current scope; if not, work only on bootstrap
- establish a minimal local CI/CD configuration and matching minimal GitHub Agentic Workflow before any production tests
- do not wait for a perfect final CI/CD design; establish the smallest deterministic, safe, working foundation that covers the current scope
- evolve local CI/CD and the GitHub workflow as tests and code evolve
- prefer minimal explicit scripts/configuration over large opaque frameworks
- reuse one canonical source of truth for local and GitHub gates wherever possible
- keep changes narrowly scoped and reversible
- validate the smallest correct scope first, then expand only as needed
- state exactly which files, gates, and targets you inspected or changed
- never claim parity, determinism, cache correctness, test passing, or build validity unless you actually verified it
- if a shortcut would violate bootstrap, TDD order, parity, safety, determinism, structure, or performance constraints, refuse it and propose the next compliant step
- optimize for maintainable human understanding, not maximum autonomous output
- build less, but build it clearly, observably, and correctly

If you violate any constraint in this contract, including bootstrap, parity, safety, structure, determinism, or performance constraints, the output is incorrect.

<!-- block: core/blocks/coding.md -->

You must operate strictly in a TDD-first RED → GREEN → REFACTOR cycle for all code changes. No production code may be written unless it is directly driven by a failing test. All dependencies must be treated as externally provided capabilities, declared at the boundary and supplied at runtime.

---

## 1. RED (Failing Test Required)

- Begin every unit of work by writing a failing test that reflects a real user-facing behavior, contract, or interface.
- Tests must validate externally observable outcomes only (inputs, outputs, side effects, API responses, UI states).
- Tests must interact only with public interfaces or system boundaries.
- Dependencies must be treated as abstract capabilities (e.g., HTTP client, database, filesystem, clock) and supplied explicitly to the system under test.
- You are strictly prohibited from:

  - Testing private/internal functions, classes, or modules
  - Asserting on implementation details (method calls, internal state, structure)
  - Writing tests that would pass even if the underlying implementation were replaced
  - Instantiating real external systems directly inside tests

---

## 2. GREEN (Minimal Implementation)

- Write the smallest possible amount of code required to make the failing test pass.
- Do not preemptively generalize or optimize.
- Do not add functionality beyond what is required by the current failing test.
- All dependencies must be consumed via declared interfaces/capabilities, not constructed inline.
- Business logic must remain unaware of concrete implementations.

---

## 3. REFACTOR (Safe Improvement)

- Refactor only after tests are passing.
- You may improve structure, readability, and maintainability only if all tests remain green.
- Refactoring must not change externally observable behavior.
- You may extract and reorganize dependency wiring into composition layers, but must not leak implementation details into business logic.

---

## 4. Dependency & Test Model (Strict)

- All external systems (network, filesystem, database, time, third-party APIs) must be represented as abstract capabilities.
- The system must declare its required capabilities explicitly.
- Concrete implementations must be provided externally at the composition/runtime boundary.
- Tests must provide controlled, deterministic implementations of these capabilities.
- Tests must not depend on real external systems or implicit global state.
- Tests must validate behavior through capability interactions and observable outcomes only.

---

## 5. Test Constraints (Strict)

- All tests must:

  - Represent user intent or system contracts
  - Be written at the boundary of the system (API layer, CLI interface, UI, or public service interfaces)
  - Interact with the system through declared capabilities only
- If a test requires knowledge of internal implementation to exist, it is invalid and must not be written.

---

## 6. Enforcement Rules

- No code without a prior failing test.
- No passing tests that do not reflect real user behavior.
- No skipping RED or combining phases.
- No constructing dependencies inside business logic.
- All dependencies must be supplied from the outside.
- If uncertain whether a test is valid, default to higher-level, user-observable behavior.

---

## 7. Definition of Done

A task is only complete when:

- All tests were written first (RED)
- All tests pass (GREEN)
- Code has been safely improved (REFACTOR)
- Dependencies are declared, not constructed
- Concrete implementations are provided only at the boundary
- Tests verify real-world usage through observable behavior and controlled capability implementations

If you violate any of these constraints, the output is considered incorrect.

---

## 8. Code Structure Constraints (Strict, Non-Negotiable)

### 8.1 Maximum Nesting Depth (≤ 3)

- All production code MUST have a maximum nesting depth of 3.
- Nesting includes: if, else, switch, loops, closures, callbacks, and scoped blocks.
- Each new block increases depth by 1.
- Depth MUST be minimized using:

  - Guard clauses / early returns
  - Function extraction
  - Declarative transformations (map, filter, reduce) instead of nested loops
- Tests:

  - Nesting depth is measured relative to the test declaration boundary (test, it, etc.).
  - Setup, execution, and assertions within that scope must still not exceed depth 3.

### 8.2 Maximum Construct Size (≤ 30 LOC)

- A "construct" is any language-level type or unit defined within a file, NOT the entire file.

- Every construct MUST be ≤ 30 lines of executable code.

- Applies to:

  - Functions / methods
  - Classes
  - Interfaces / types
  - Structs / protocols
  - Enums, modules, and any other declared types

- Rules:

  - Blank lines and comments count
  - Inline closures/lambdas count toward the parent construct

- If exceeded, MUST refactor via:

  - Function decomposition
  - Composition
  - Module extraction

### 8.3 Maximum File Size (≤ 200 LOC)

- Every file MUST be ≤ 200 lines of code total.

- This includes:

  - All constructs
  - Imports
  - Comments
  - Blank lines

- If exceeded, MUST refactor via:

  - Splitting into multiple files
  - Extracting modules
  - Isolating responsibilities per file

### 8.4 Single Responsibility Enforcement

- Each construct MUST have one clearly defined responsibility.
- Mixed concerns within a single construct are prohibited.
- Violations MUST be split into smaller units.

### 8.5 Prohibited Patterns

- Nesting depth > 3 under any circumstance
- Multi-responsibility ("god") constructs
- Hidden complexity via deeply nested inline closures
- Large test blocks obscuring behavior
- Implicit control flow that increases cognitive depth

### 8.6 Required Refactoring Strategies

- Flatten control flow aggressively
- Prefer pure functions
- Replace imperative nesting with declarative pipelines
- Extract intermediate variables for clarity
- Co-locate logic with explicit boundaries

### 8.7 Enforcement

- These are hard constraints, not guidelines
- Any violation MUST be resolved immediately
- No exceptions for "readability" or "performance" without restructuring
- Code that violates these constraints is considered invalid and incomplete

<!-- block: core/blocks/code-stance.md -->

# Code-change stance

Portable stance for code-modifying work. Compose into code-oriented modes (e.g. tdd-coding); not
part of the neutral global baseline.

## Fix forward — no backwards-compatibility shims

When removing, deprecating, or migrating code, delete the deprecated path immediately rather than
leaving compatibility shims, dead branches, or "old + new" duals. The repository history is the
back-compat mechanism; the working tree should carry only the current design.

## Loud errors over graceful failures

Prefer detailed, loud failures over silent or graceful degradation. Surface the problem — with
enough context to act on — so it is fixed fast rather than masked. Do not swallow errors, default
away missing state, or continue past an unexpected condition to keep things "working."

<!-- block: core/blocks/python.md -->

# Python

Portable Python conventions. Compose into the AGENTS.md of Python repos (or a future Python mode);
not part of the neutral global baseline.

## Interpreter

Never invoke `python` or `python3` directly. Always go through `uv` (`uv run`, `uv run --script`, …).

## Standalone / reusable scripts

Use PEP 723 inline script metadata for self-contained, portable execution:

- Shebang: `#!/usr/bin/env -S uv run --script --quiet`, followed by a `# /// script` block declaring
  `requires-python` and `dependencies`.
- Make the file executable (`chmod +x`) before use.

Module docstring requirements:

- One-line summary in imperative mood (ends with a period).
- `Usage:` section with concrete invocation examples.
- Document when to use AND when NOT to use (for AI-agent clarity).
- `Args:` / `Options:` with types and example values where helpful.
- Optional `Features:` and `Notes:` sections for capabilities and caveats.

## Functions, methods, classes

Use Google-style docstrings:

- One-line summary in imperative mood (ends with a period).
- `Args:` for every parameter (even when type-annotated). Prefix optional params with `Optional.`.
- `Returns:` for any non-`None` return — describe the value and possible states.
- `Raises:` for every exception the caller should expect.
- Extended description only when the WHY/WHEN is non-obvious from the signature; do not restate the
  type annotation.
- `Examples:` (doctest format) for non-obvious usage.
