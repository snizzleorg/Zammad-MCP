"""Entry point for the Zammad MCP server."""

from .config import TransportConfig, TransportType
from .logging_config import configure_logging


def main() -> None:
    """Run the MCP server with configured transport.

    Transport is configured via environment variables:
    - MCP_TRANSPORT: 'stdio' (default), 'http' (streamable-http), or 'sse'
    - MCP_HOST: Host for HTTP transport (default: 127.0.0.1)
    - MCP_PORT: Port for HTTP transport (default: 8000)
    """
    # Configure logging before importing server code to prevent stdout leakage.
    configure_logging()

    # Load and validate transport configuration before server module initialization.
    config = TransportConfig.from_env()
    config.validate()

    from .server import mcp  # noqa: PLC0415

    if config.transport == TransportType.HTTP:
        mcp.run(transport="http", host=config.host, port=config.port)
    elif config.transport == TransportType.SSE:
        mcp.run(transport="sse", host=config.host, port=config.port)
    else:
        mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
