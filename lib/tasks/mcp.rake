namespace :mcp do
  desc "Generate a new MCP access token"
  task :generate_token, [ :name ] => :environment do |_t, args|
    name = args[:name] || "default"
    token, plaintext = McpAccessToken.generate!(name: name)

    puts "token created: #{token.name}"
    puts "preview: ...#{token.last_token_preview}"
    puts ""
    puts "plaintext (copy now — it won't be shown again):"
    puts plaintext
    puts ""
    puts "test with:"
    puts "  curl -X POST http://localhost:3001/mcp \\"
    puts "    -H 'Content-Type: application/json' \\"
    puts "    -H 'Accept: application/json' \\"
    puts "    -H 'Authorization: Bearer #{plaintext}' \\"
    puts '    -d \'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}\''
  end

  desc "List all MCP access tokens"
  task list_tokens: :environment do
    tokens = McpAccessToken.order(created_at: :desc)
    if tokens.empty?
      puts "no tokens."
    else
      tokens.each do |t|
        status = t.revoked? ? "revoked" : "active"
        last_used = t.last_used_at&.strftime("%Y-%m-%d %H:%M") || "never"
        puts "#{t.id}. #{t.name} (#{status}) — ...#{t.last_token_preview} — last used: #{last_used}"
      end
    end
  end

  desc "Revoke an MCP access token by ID"
  task :revoke_token, [ :id ] => :environment do |_t, args|
    token = McpAccessToken.find(args[:id])
    token.revoke!
    puts "revoked: #{token.name} (...#{token.last_token_preview})"
  end
end
