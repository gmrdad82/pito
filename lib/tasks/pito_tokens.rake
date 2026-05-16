# Phase 32 follow-up (2026-05-16). Operator-only management of
# `ApiToken` rows.
#
# pito is single-user (ADR 0003). The web-side `/settings/tokens/*`
# management surface was dropped in this follow-up; operators mint /
# list / revoke API tokens from the shell.
#
# The pre-existing `lib/tasks/tokens.rake` (`tokens:create` /
# `tokens:list` / `tokens:revoke`) is intentionally left in place —
# it predates this follow-up and remains valid. The new
# `pito:tokens:*` surface is the canonical, namespace-consistent entry
# point that matches `pito:user:reset_totp` /
# `pito:oauth_apps:*` style.
#
# Style + structure: matches `pito:user:reset_totp` in
# `lib/tasks/pito.rake` — explicit argument parsing, idempotent where
# the verb allows, non-zero `exit` on missing or unknown inputs,
# stderr for errors, stdout for the operator-facing payload.
#
# Usage:
#   bin/rails pito:tokens:list
#   bin/rails 'pito:tokens:mint[name,scope1+scope2+...]'
#   bin/rails 'pito:tokens:revoke[id_or_name]'
#
# Scope syntax mirrors `tokens:create` — `+`-separated to avoid the
# Thor comma-in-task-args escape ceremony.
namespace :pito do
  namespace :tokens do
    desc "List every ApiToken (id, name, scopes, status, last_used_at, created_at). " \
         "Does NOT print the plaintext token."
    task list: :environment do
      tokens = ApiToken.order(:created_at)
      if tokens.empty?
        puts "no API tokens minted."
        next
      end

      tokens.each do |token|
        status = if token.revoked?
                   "revoked"
        elsif token.expired?
                   "expired"
        else
                   "active"
        end
        last_used = token.last_used_at&.utc&.iso8601 || "never"
        scopes    = Array(token.scopes).join("+")
        puts "#{token.id}. #{token.name}"
        puts "    scopes:       #{scopes}"
        puts "    status:       #{status}"
        puts "    preview:      ...#{token.last_token_preview}"
        puts "    last_used_at: #{last_used}"
        puts "    created_at:   #{token.created_at.utc.iso8601}"
      end
    end

    desc "Mint a new ApiToken for the seeded owner user (the first User row). " \
         "Usage: pito:tokens:mint[name,scope1+scope2+...]"
    task :mint, [ :name, :scopes ] => :environment do |_t, args|
      name = args[:name].to_s.strip
      raw_scopes = args[:scopes].to_s.split("+").map(&:strip).reject(&:empty?)

      if name.empty?
        warn "name required: bin/rails 'pito:tokens:mint[<name>,<scopes>]'"
        exit 1
      end

      if raw_scopes.empty?
        warn "scopes required: bin/rails 'pito:tokens:mint[<name>,<scope1>+<scope2>+...]' " \
             "(allowed: #{Scopes::ALL.join(', ')})"
        exit 1
      end

      invalid = raw_scopes - Scopes::ALL
      if invalid.any?
        warn "invalid scopes: #{invalid.join(', ')} (allowed: #{Scopes::ALL.join(', ')})"
        exit 1
      end

      owner = User.first
      if owner.nil?
        warn "no User seeded — run bin/rails db:seed first."
        exit 1
      end

      token, plaintext = ApiToken.generate!(
        user:   owner,
        name:   name,
        scopes: raw_scopes
      )

      puts "=" * 64
      puts "API token created — save the plaintext now."
      puts "It cannot be retrieved later — only the digest is stored."
      puts "=" * 64
      puts "  id:        #{token.id}"
      puts "  name:      #{token.name}"
      puts "  scopes:    #{token.scopes.join('+')}"
      puts "  preview:   ...#{token.last_token_preview}"
      puts "  plaintext: #{plaintext}"
      puts "=" * 64
    end

    desc "Revoke (soft-delete) an ApiToken by id or name. Usage: pito:tokens:revoke[id_or_name]"
    task :revoke, [ :id_or_name ] => :environment do |_t, args|
      lookup = args[:id_or_name].to_s.strip
      if lookup.empty?
        warn "id_or_name required: bin/rails 'pito:tokens:revoke[<id_or_name>]'"
        exit 1
      end

      token = find_api_token(lookup)
      if token.nil?
        warn "token not found: #{lookup}"
        exit 1
      end

      if token.revoked?
        puts "token already revoked: #{token.name} (id=#{token.id})"
        next
      end

      token.revoke!
      puts "revoked API token '#{token.name}' (id=#{token.id}, preview=...#{token.last_token_preview})."
    end

    # Helper — numeric ids resolve by primary key first, then fall
    # through to name; non-numeric inputs go straight to name lookup.
    def find_api_token(lookup)
      if lookup.match?(/\A\d+\z/)
        ApiToken.find_by(id: lookup.to_i) || ApiToken.find_by(name: lookup)
      else
        ApiToken.find_by(name: lookup)
      end
    end
  end
end
