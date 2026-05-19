# frozen_string_literal: true

# Phase 7.5 — Doorkeeper scope soft-clip.
#
# Doorkeeper's default scope validation is strict: if a client requests
# any scope that is NOT inside its application's per-app `scopes`
# whitelist, the entire authorization request is rejected with
# `invalid_scope`. This is incompatible with most real OAuth clients
# (Claude.ai's MCP connector, GitHub Apps, generic OAuth libraries)
# which advertise / request the full set of scopes the *server* knows
# about and expect the server to issue an intersection.
#
# Standard OAuth servers like Google and GitHub clip rather than
# reject; clients including Claude.ai's MCP connector rely on this.
# Strict-rejection mode breaks integrations and forces per-client
# metadata workarounds we don't want.
#
# This patch switches to a soft-clip model:
#
#   issued_scopes = requested ∩ app.scopes ∩ server.scopes
#
# Validation rules:
#   - Every requested scope must exist in `server.scopes` (Scopes::ALL).
#     Rationale: we never silently expand beyond what the server
#     actually supports — an unknown scope is still an error.
#   - The intersection with `app.scopes` must be non-empty. Rationale:
#     we cannot issue an empty-scope grant, and a client whose request
#     shares no scope with the application has misconfigured client_id.
#   - Otherwise, the issued scope string is the intersection. The
#     consent screen and the issued grant / token both reflect ONLY
#     what the user is actually granting.
#
# Implementation: two private overrides on `Doorkeeper::OAuth::PreAuthorization`:
#
#   - `validate_scopes` — replaces the strict `ScopeChecker.valid?`
#     with the rules above.
#   - `scopes` (public) — returns the clipped intersection so the
#     downstream `Authorization::Code#access_grant_attributes` writes
#     the clipped list onto the access grant. From there, the access
#     token inherits the clipped scope list automatically.
#
# Spec coverage: the dedicated `spec/requests/oauth_scope_clip_spec.rb`
# was retired in Phase 29 (MCP cut, 2026-05-19) when the catalog
# collapsed to a single scope — clip math against a one-element catalog
# has no meaningful failure surface. The
# `spec/requests/oauth_authorization_spec.rb` round-trip still
# exercises the patch end-to-end.
Rails.application.config.after_initialize do
  Doorkeeper::OAuth::PreAuthorization.class_eval do
    # Public override. Returns the clipped intersection
    # `(requested ∩ app.scopes ∩ server.scopes)` as a `Doorkeeper::OAuth::Scopes`.
    # When the request omits a scope param, we fall back to the
    # original behavior (server defaults filtered by `app.scopes`).
    def scopes
      requested = @scope.to_s.strip
      return Doorkeeper::OAuth::Scopes.from_string(scope) if requested.empty?

      requested_set = Doorkeeper::OAuth::Scopes.from_string(requested)
      server_set    = server.scopes
      app_set       = client&.scopes

      # First clip to server scopes (drop anything the server doesn't
      # know about — `validate_scopes` already rejected the request if
      # any unknown scope was present, so this is a no-op when reached
      # via the happy path).
      clipped = server_set.allowed(requested_set.all)

      # Then clip to per-app scopes when the application defines any.
      if app_set.present? && !app_set.empty?
        clipped = app_set.allowed(clipped.all)
      end

      clipped
    end

    private

    # Replaces Doorkeeper's strict `Helpers::ScopeChecker.valid?` call
    # with the soft-clip rules described in the file header.
    def validate_scopes
      requested = @scope.to_s.strip

      # No scope requested — defer to Doorkeeper defaults (handled by
      # `validate_params`, which fails when both `@scope` and
      # `server.default_scopes` are blank).
      return true if requested.empty?

      # Tab / newline / carriage-return inside a scope string is the
      # one syntactic check Doorkeeper's ScopeChecker enforces. Keep
      # it; the OAuth spec forbids whitespace other than a single
      # space between scopes.
      return false if requested =~ /[\n\r\t]/

      requested_set = Doorkeeper::OAuth::Scopes.from_string(requested)
      server_set    = server.scopes

      # Reject scopes outside the server catalog (`Scopes::ALL`).
      # Soft-clip is bounded by what the server actually supports.
      return false unless server_set.has_scopes?(requested_set)

      # Reject when the intersection with the application's scopes is
      # empty — no grantable scope means there is nothing to issue.
      app_set = client&.scopes
      if app_set.present? && !app_set.empty?
        intersection = app_set.allowed(requested_set.all)
        return false if intersection.empty?
      end

      true
    end
  end
end
