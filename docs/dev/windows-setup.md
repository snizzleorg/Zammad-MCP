# Windows Setup Guide

This guide covers setting up the Zammad MCP server on Windows for development, including the
optional PII anonymization feature (vendored `llm-anon-core`).

For the general project overview, configuration reference, and non-Windows instructions, see
[README.md](../../README.md). This guide only covers what differs on Windows.

## Prerequisites

- Python 3.10–3.13
- Git for Windows
- `uv` (install via PowerShell):

  ```powershell
  powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
  ```

  If PATH isn't picked up immediately, open a new terminal.

## Quick setup

```powershell
git clone https://github.com/basher83/zammad-mcp.git
cd zammad-mcp
.\scripts\setup.ps1
```

The script will:

1. Install `uv` if it isn't already on PATH.
2. Create `.venv` and activate it.
3. Ask whether to enable PII anonymization support (see below) — answer `N` if you don't need it.
4. Install dependencies (`uv pip install -e ".[dev]"`, or `.[dev,pii]"` if you opted in).
5. Copy `.env.example` to `.env` if one doesn't already exist.

Then edit `.env` with your Zammad credentials:

```env
ZAMMAD_URL=https://your-instance.zammad.com/api/v1
ZAMMAD_HTTP_TOKEN=your-api-token
```

Alternative: `./scripts/uv/dev-setup.py` is an interactive wizard that also detects Windows and
walks through the same steps with more explanation — use it if you want more hand-holding.

## PII anonymization (vendored `llm-anon-core`)

`llm-anon-core` is a private dependency, sourced by default from an internal git server
(`git.b.picoquant.com`) that most contributors won't have access to. For local development it's
vendored instead: cloned into `vendor/` (gitignored) and referenced from `pyproject.toml` via a
local `path` source.

`scripts/setup.ps1` automates this when you answer `y` to the PII prompt:

1. Clones `https://git.b.picoquant.com/ruettinger/llm-anon-core.git` into `vendor\llm-anon-core`
   (skipped if that folder already exists).
2. Edits `pyproject.toml`'s `[tool.uv.sources]` block to point `llm-anon-core` at the local vendored
   path instead of the git URL. **This is a local-only change — do not commit it.** If you ever
   need to revert it: `git checkout -- pyproject.toml`.
3. Installs with the `pii` extra: `uv pip install -e ".[dev,pii]"`.
4. Uncomments `PII_FILTER_ENABLED=true` in the newly created `.env`.

### Doing it manually

If you skipped the prompt, or need to redo it:

```powershell
git clone https://git.b.picoquant.com/ruettinger/llm-anon-core.git vendor\llm-anon-core
```

Edit `pyproject.toml`:

```toml
[tool.uv.sources]
llm-anon-core = { path = "vendor/llm-anon-core", editable = true }
# llm-anon-core = { git = "https://git.b.picoquant.com/ruettinger/llm-anon-core.git" }
```

```powershell
uv sync --extra pii
```

Then set `PII_FILTER_ENABLED=true` in `.env`.

### Windows-specific notes

- spaCy's small NER models (EN/DE/FR/ES/IT/PL/RU) are pulled as prebuilt wheels directly from
  GitHub releases during `uv sync`/`uv pip install` — there's no separate `spacy download` step,
  and no C/C++ build toolchain needed **on Windows x64** (prebuilt wheels exist there for
  spaCy/Presidio).
- **Windows on ARM64** is the one real risk spot: prebuilt spaCy wheels may not exist for that
  target. If `uv sync --extra pii` fails trying to build spaCy from source, use WSL2 (Ubuntu) and
  follow the Linux instructions in the main README instead.
- `pyproject.toml` after the vendor toggle is a locally modified tracked file. Running
  `git status` will show it as modified — that's expected and it should stay uncommitted. If you
  pull upstream changes to `pyproject.toml` later, you may get a merge conflict on that one line;
  resolve it by re-running the toggle (or `git checkout -- pyproject.toml` then redo it).

## Running the server

```powershell
.\.venv\Scripts\activate
uv run python -m mcp_zammad
```

## Claude Desktop configuration (Windows)

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "zammad": {
      "command": "uv",
      "args": ["run", "--directory", "C:\\path\\to\\zammad-mcp", "mcp-zammad"],
      "env": {
        "ZAMMAD_URL": "https://your-instance.zammad.com/api/v1",
        "ZAMMAD_HTTP_TOKEN": "your-api-token",
        "PII_FILTER_ENABLED": "true"
      }
    }
  }
}
```

Use the full path to your clone (double backslashes), not a relative one — Claude Desktop launches
the server from its own working directory, not yours.

**Note:** if you use `--directory` pointing at a checkout that already has a populated `.env`, the
`env` block above is technically redundant — see the explanation below for why the docs show both.

## Why do `ZAMMAD_URL` / `PII_FILTER_ENABLED` need to be set in both `.env` *and* the Claude Desktop config?

They don't — you only need one, and which one depends on how the server process gets started:

- **Running via `.env`**: on startup, `_bootstrap_env()` in `mcp_zammad/server.py` calls
  `load_dotenv()` against a `.env` file found in the process's current working directory. If you
  launch Claude Desktop's config with `"args": ["run", "--directory", "C:\\path\\to\\zammad-mcp", "mcp-zammad"]`,
  `uv run --directory ...` sets that as the working directory, so the `.env` in your checkout is
  found and loaded automatically. No need to duplicate values into `env` in that case.
- **Running via the Claude Desktop `env` block**: Claude Desktop launches the MCP server as a
  subprocess with a clean environment — it does not inherit your shell profile or read your
  project's `.env` for you. If there's no `.env` at the working directory the process ends up in
  (e.g. you're using the `uvx --from git+https://github.com/...` install method, which has no local
  checkout at all, or Docker, which doesn't mount your `.env` by default), the `env` block is the
  *only* way credentials reach the process.
- Python's `dotenv.load_dotenv()` does **not** override variables already present in the process
  environment. So if a variable is set in both places, the Claude Desktop `env` value always wins;
  `.env` only fills in what isn't already set.

The README shows both in its examples mainly to make the Claude Desktop config self-contained and
portable regardless of install method (uvx/Docker/local checkout), not because both are strictly
required together. For local development with `--directory` pointed at your checkout, `.env` alone
is sufficient — you can omit `ZAMMAD_URL`/`ZAMMAD_HTTP_TOKEN`/`PII_FILTER_ENABLED` from the Claude
Desktop `env` block if you'd rather manage them in one place.
