# Phase 3 — Step B (5b-token-and-auth-concern.md) — token CRUD rake tasks.
#
# Renamed from `mcp:generate_token` / `mcp:list_tokens` / `mcp:revoke_token`
# to the namespace-neutral `tokens:create` / `tokens:list` / `tokens:revoke`,
# matching the model rename `McpAccessToken` → `ApiToken`.
#
# Usage:
#   bin/rails "tokens:create[<name>,<scope1>+<scope2>+...]"
#   bin/rails tokens:list
#   bin/rails "tokens:revoke[<id>]"
#
# Scopes are passed as a `+`-separated list (Thor disallows commas inside
# task args without escaping). Example:
#   bin/rails "tokens:create[dev-default,dev:read+dev:write]"
#
# Plaintext is shown once and then unreachable; copy it before closing
# the terminal.
namespace :tokens do
  desc "Generate a new API token. Usage: tokens:create[name,scope1+scope2+...]"
  task :create, [ :name, :scopes ] => :environment do |_t, args|
    name   = (args[:name] || "default").to_s
    scopes = (args[:scopes] || "dev:read+dev:write").to_s.split("+").map(&:strip).reject(&:empty?)

    user = User.first

    if user.nil?
      abort "no User seeded — run bin/rails db:seed first"
    end

    invalid = scopes - Scopes::ALL
    if invalid.any?
      abort "invalid scopes: #{invalid.join(", ")} (allowed: #{Scopes::ALL.join(", ")})"
    end

    token, plaintext = ApiToken.generate!(
      user: user,
      name: name,
      scopes: scopes
    )

    puts "token created: #{token.name}"
    puts "scopes: #{token.scopes.join(", ")}"
    puts "preview: ...#{token.last_token_preview}"
    puts ""
    puts "plaintext (copy now — it won't be shown again):"
    puts plaintext
    puts ""
    puts "test with:"
    puts "  curl -X POST http://localhost:3028/mcp \\"
    puts "    -H 'Content-Type: application/json' \\"
    puts "    -H 'Accept: application/json' \\"
    puts "    -H 'Authorization: Bearer #{plaintext}' \\"
    puts '    -d \'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}\''
  end

  desc "List all API tokens"
  task list: :environment do
    tokens = ApiToken.order(created_at: :desc)
    if tokens.empty?
      puts "no tokens."
    else
      tokens.each do |t|
        status = if t.revoked?
                   "revoked"
        elsif t.expired?
                   "expired"
        else
                   "active"
        end
        last_used = t.last_used_at&.strftime("%Y-%m-%d %H:%M") || "never"
        scopes = Array(t.scopes).join("+")
        puts "#{t.id}. #{t.name} [#{scopes}] (#{status}) — ...#{t.last_token_preview} — last used: #{last_used}"
      end
    end
  end

  desc "Revoke an API token by ID. Usage: tokens:revoke[id]"
  task :revoke, [ :id ] => :environment do |_t, args|
    abort "id required: bin/rails 'tokens:revoke[<id>]'" if args[:id].to_s.empty?

    token = ApiToken.find(args[:id])
    token.revoke!
    puts "revoked: #{token.name} (...#{token.last_token_preview})"
  end
end
