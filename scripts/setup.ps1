# Quick setup script for Zammad MCP server with uv on Windows

Write-Host "Setting up Zammad MCP Server..." -ForegroundColor Green

# Check if uv is installed
try {
    $null = Get-Command uv -ErrorAction Stop
} catch {
    Write-Host "Installing uv..." -ForegroundColor Yellow
    Write-Host "This will download and execute uv installer from https://astral.sh/uv/install.ps1" -ForegroundColor Yellow
    $confirmation = Read-Host "Continue? (y/N)"
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" | Invoke-Expression
        Write-Host ""
        Write-Host "Note: PATH may need to be updated for uv to work in new terminals." -ForegroundColor Yellow
        Write-Host "The installer should have updated your PATH automatically." -ForegroundColor DarkGray
    } else {
        Write-Host "Installation cancelled. Please install uv manually." -ForegroundColor Red
        exit 1
    }
}

# Create virtual environment
Write-Host "Creating virtual environment..." -ForegroundColor Yellow
uv venv

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& .\.venv\Scripts\activate

# Optional: PII anonymization support (vendored llm-anon-core)
$extras = "dev"
$piiConfirm = Read-Host "Enable PII anonymization support? Requires access to the internal llm-anon-core repo (y/N)"
if ($piiConfirm -eq 'y' -or $piiConfirm -eq 'Y') {
    $vendorPath = "vendor\llm-anon-core"
    if (!(Test-Path $vendorPath)) {
        Write-Host "Cloning llm-anon-core into $vendorPath..." -ForegroundColor Yellow
        git clone https://git.b.picoquant.com/ruettinger/llm-anon-core.git $vendorPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to clone llm-anon-core. Continuing without the pii extra." -ForegroundColor Red
            $piiConfirm = 'N'
        }
    } else {
        Write-Host "Found existing $vendorPath, using it." -ForegroundColor DarkGray
    }
}

if ($piiConfirm -eq 'y' -or $piiConfirm -eq 'Y') {
    Write-Host "Pointing pyproject.toml at the vendored copy (local-only change - do not commit)..." -ForegroundColor Yellow
    (Get-Content pyproject.toml -Raw) `
        -replace '(?m)^llm-anon-core = \{ git = "https://git\.b\.picoquant\.com/ruettinger/llm-anon-core\.git" \}$', '#llm-anon-core = { git = "https://git.b.picoquant.com/ruettinger/llm-anon-core.git" }' `
        -replace '(?m)^#llm-anon-core = \{ path = "vendor/llm-anon-core", editable = true \}$', 'llm-anon-core = { path = "vendor/llm-anon-core", editable = true }' |
        Set-Content pyproject.toml -NoNewline
    $extras = "dev,pii"
}

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
uv pip install -e ".[$extras]"

# Copy .env.example if .env doesn't exist
if (!(Test-Path .env)) {
    Write-Host "Creating .env file from template..." -ForegroundColor Yellow
    Copy-Item .env.example .env
    if ($piiConfirm -eq 'y' -or $piiConfirm -eq 'Y') {
        (Get-Content .env -Raw) -replace '(?m)^# PII_FILTER_ENABLED=true$', 'PII_FILTER_ENABLED=true' |
            Set-Content .env -NoNewline
    }
    Write-Host "Please edit .env file with your Zammad credentials" -ForegroundColor Red
}

Write-Host ""
Write-Host "Setup complete! To start using the server:" -ForegroundColor Green
Write-Host "1. Edit .env file with your Zammad credentials"
Write-Host "2. Activate the virtual environment: .\.venv\Scripts\activate"
Write-Host "3. Run the server: python -m mcp_zammad"