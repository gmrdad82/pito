# Puma config for MCP HTTP server (separate process from web app)
# Started via: bin/mcp-web

port ENV.fetch("MCP_PORT", 3001)
environment ENV.fetch("RAILS_ENV", "development")
workers ENV.fetch("MCP_WORKERS", 1).to_i
threads_count = ENV.fetch("MCP_THREADS", 5).to_i
threads threads_count, threads_count

pidfile ENV.fetch("MCP_PIDFILE", "tmp/pids/mcp.pid")

# Preload for faster worker boot + copy-on-write
preload_app!
