# Phase 32 follow-up (2026-05-16). Operator-only management of
# Doorkeeper OAuth applications.
#
# pito is single-user (ADR 0003). The web-side
# `/settings/oauth_applications/*` management surface was dropped in
# this follow-up; the Doorkeeper handshake routes (`/oauth/authorize`,
# `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`) stay live so
# OAuth clients (Claude Desktop's MCP custom connector being the
# motivating one) keep working. Operators register / inspect / revoke
# applications from the shell.
#
# Style + structure: matches `pito:user:reset_totp` in
# `lib/tasks/pito.rake` — explicit argument parsing, idempotent where
# the verb allows, non-zero `exit` on missing or unknown inputs,
# stderr for errors, stdout for the operator-facing payload.
#
# Usage:
#   bin/rails pito:oauth_apps:list
#   bin/rails 'pito:oauth_apps:mint[name,redirect_uri,scope1+scope2+...]'
#   bin/rails 'pito:oauth_apps:show[id_or_client_id]'
#   bin/rails 'pito:oauth_apps:revoke[id_or_client_id]'
#   bin/rails 'pito:oauth_apps:revoke[id_or_client_id,force]'
#
# Scope syntax mirrors `tokens:create` — `+`-separated to avoid the
# Thor comma-in-task-args escape ceremony. Defaults to `Scopes::ALL`
# when the third argument is omitted.
namespace :pito do
  namespace :oauth_apps do
    desc "List every Doorkeeper application (id, name, client_id, redirect_uri, scopes, created_at)."
    task list: :environment do
      apps = OauthApplication.order(:created_at)
      if apps.empty?
        puts "no OAuth applications registered."
        next
      end

      apps.each do |app|
        puts "#{app.id}. #{app.name}"
        puts "    client_id:    #{app.uid}"
        puts "    redirect_uri: #{app.redirect_uri}"
        puts "    scopes:       #{app.scopes}"
        puts "    confidential: #{app.confidential? ? 'yes' : 'no'}"
        puts "    created_at:   #{app.created_at.utc.iso8601}"
      end
    end

    desc "Mint a new Doorkeeper application. " \
         "Usage: pito:oauth_apps:mint[name,redirect_uri,scope1+scope2+...]"
    task :mint, [ :name, :redirect_uri, :scopes ] => :environment do |_t, args|
      name = args[:name].to_s.strip
      redirect_uri = args[:redirect_uri].to_s.strip
      raw_scopes = args[:scopes].to_s.split("+").map(&:strip).reject(&:empty?)
      raw_scopes = Scopes::ALL.dup if raw_scopes.empty?

      if name.empty?
        warn "name required: bin/rails 'pito:oauth_apps:mint[<name>,<redirect_uri>,<scopes?>]'"
        exit 1
      end

      if redirect_uri.empty?
        warn "redirect_uri required: bin/rails 'pito:oauth_apps:mint[<name>,<redirect_uri>,<scopes?>]'"
        exit 1
      end

      invalid = raw_scopes - Scopes::ALL
      if invalid.any?
        warn "invalid scopes: #{invalid.join(', ')} (allowed: #{Scopes::ALL.join(', ')})"
        exit 1
      end

      app = OauthApplication.new(
        name: name,
        redirect_uri: redirect_uri,
        scopes: raw_scopes.join(" "),
        confidential: true
      )

      unless app.save
        warn "failed to create application: #{app.errors.full_messages.join('; ')}"
        exit 1
      end

      # Doorkeeper's default secret strategy is `Plain`, so reading the
      # secret back after save returns the same plaintext the controller
      # used to surface on the one-time create page. If a future config
      # switches to a hashing strategy, `plaintext_secret` (set during
      # save) is the only way to capture the original value.
      plaintext_secret = app.plaintext_secret || app.secret

      puts "=" * 64
      puts "OAuth application created — save the client_secret now."
      puts "It cannot be retrieved later if Doorkeeper is reconfigured"
      puts "to hash application secrets."
      puts "=" * 64
      puts "  id:            #{app.id}"
      puts "  name:          #{app.name}"
      puts "  client_id:     #{app.uid}"
      puts "  client_secret: #{plaintext_secret}"
      puts "  redirect_uri:  #{app.redirect_uri}"
      puts "  scopes:        #{app.scopes}"
      puts "  confidential:  #{app.confidential? ? 'yes' : 'no'}"
      puts "=" * 64
    end

    desc "Show one application's metadata (NOT secret). Usage: pito:oauth_apps:show[id_or_client_id]"
    task :show, [ :id_or_client_id ] => :environment do |_t, args|
      lookup = args[:id_or_client_id].to_s.strip
      if lookup.empty?
        warn "id_or_client_id required: bin/rails 'pito:oauth_apps:show[<id_or_client_id>]'"
        exit 1
      end

      app = find_application(lookup)
      if app.nil?
        warn "application not found: #{lookup}"
        exit 1
      end

      puts "  id:            #{app.id}"
      puts "  name:          #{app.name}"
      puts "  client_id:     #{app.uid}"
      puts "  redirect_uri:  #{app.redirect_uri}"
      puts "  scopes:        #{app.scopes}"
      puts "  confidential:  #{app.confidential? ? 'yes' : 'no'}"
      puts "  created_at:    #{app.created_at.utc.iso8601}"
    end

    desc "Revoke (destroy) an application and revoke its outstanding tokens + grants. " \
         "Usage: pito:oauth_apps:revoke[id_or_client_id,force?]"
    task :revoke, [ :id_or_client_id, :force ] => :environment do |_t, args|
      lookup = args[:id_or_client_id].to_s.strip
      forced = args[:force].to_s == "force" || args[:force].to_s == "true" || args[:force].to_s == "yes"

      if lookup.empty?
        warn "id_or_client_id required: bin/rails 'pito:oauth_apps:revoke[<id_or_client_id>,force?]'"
        exit 1
      end

      app = find_application(lookup)
      if app.nil?
        warn "application not found: #{lookup}"
        exit 1
      end

      unless forced
        warn "refusing to revoke without force=true. " \
             "Re-run as: bin/rails 'pito:oauth_apps:revoke[#{lookup},force]'"
        exit 1
      end

      revoked_at_now = Time.current
      tokens_revoked = 0
      grants_revoked = 0

      ActiveRecord::Base.transaction do
        tokens_revoked = OauthAccessToken
                           .where(application_id: app.id, revoked_at: nil)
                           .update_all(revoked_at: revoked_at_now)
        grants_revoked = OauthAccessGrant
                           .where(application_id: app.id, revoked_at: nil)
                           .update_all(revoked_at: revoked_at_now)
        app.destroy!
      end

      puts "revoked OAuth application '#{app.name}' (id=#{app.id}) — " \
           "tokens=#{tokens_revoked}, grants=#{grants_revoked}."
    end

    # Helper — resolve either a numeric id or the Doorkeeper uid string.
    def find_application(lookup)
      if lookup.match?(/\A\d+\z/)
        OauthApplication.find_by(id: lookup.to_i) || OauthApplication.find_by(uid: lookup)
      else
        OauthApplication.find_by(uid: lookup)
      end
    end
  end
end
