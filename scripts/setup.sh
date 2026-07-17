#!/bin/bash
# Quick setup script for Zammad MCP server with uv

set -euo pipefail

echo "Setting up Zammad MCP Server..."

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Add uv to PATH for this session
    export PATH="$HOME/.cargo/bin:$PATH"
    echo ""
    echo "Note: PATH updated for current session only."
    echo "Add ~/.cargo/bin to your shell's PATH permanently."
fi

# Create virtual environment
echo "Creating virtual environment..."
uv venv

# Activate virtual environment
echo "Activating virtual environment..."
source .venv/bin/activate

# Optional: PII anonymization support (vendored llm-anon-core)
extras="dev"
read -r -p "Enable PII anonymization support? Requires access to the internal llm-anon-core repo (y/N): " pii_confirm
if [[ "$pii_confirm" =~ ^[Yy]$ ]]; then
    vendor_path="vendor/llm-anon-core"
    if [ ! -d "$vendor_path" ]; then
        echo "Cloning llm-anon-core into $vendor_path..."
        if git clone https://git.b.picoquant.com/ruettinger/llm-anon-core.git "$vendor_path"; then
            :
        else
            echo "Failed to clone llm-anon-core. Continuing without the pii extra." >&2
            pii_confirm="n"
        fi
    else
        echo "Found existing $vendor_path, using it."
    fi
fi

if [[ "$pii_confirm" =~ ^[Yy]$ ]]; then
    echo "Pointing pyproject.toml at the vendored copy (local-only change — do not commit)..."
    sed -i.bak \
        -e 's|^llm-anon-core = { git = "https://git\.b\.picoquant\.com/ruettinger/llm-anon-core\.git" }$|#llm-anon-core = { git = "https://git.b.picoquant.com/ruettinger/llm-anon-core.git" }|' \
        -e 's|^#llm-anon-core = { path = "vendor/llm-anon-core", editable = true }$|llm-anon-core = { path = "vendor/llm-anon-core", editable = true }|' \
        pyproject.toml
    rm -f pyproject.toml.bak
    extras="dev,pii"
fi

# Install dependencies
echo "Installing dependencies..."
uv pip install -e ".[$extras]"

# Copy .env.example if .env doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    if [[ "$pii_confirm" =~ ^[Yy]$ ]]; then
        sed -i.bak -e 's|^# PII_FILTER_ENABLED=true$|PII_FILTER_ENABLED=true|' .env
        rm -f .env.bak
    fi
    echo "Please edit .env file with your Zammad credentials"
fi

echo ""
echo "Setup complete! To start using the server:"
echo "1. Edit .env file with your Zammad credentials"
echo "2. Activate the virtual environment: source .venv/bin/activate"
echo "3. Run the server: python -m mcp_zammad"