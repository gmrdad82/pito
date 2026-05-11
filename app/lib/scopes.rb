# Phase 10 — MCP scope catalog collapse (ADR 0004).
# Phase 25 — 01d — adds the `auth` scope.
#
# Single source of truth for token scopes across the entire stack. Three
# scopes:
#
#   - `dev`  — dev knowledge base read + capture (docs/, notes).
#   - `app`  — application data — channels, videos, projects, calendar, etc.
#   - `auth` — authentication / login security surface — pending login
#              attempts, approve / block / unblock / purge, blocked
#              locations, auth audit log. Opt-in per token; not granted
#              by default because the surface is privileged.
#
# Strip-on-release: `dev` is dropped from the catalog when
# `Rails.application.config.x.mcp.expose_dev_scope == false` (production).
# `auth` follows the same strip-on-release pattern via
# `Rails.application.config.x.mcp.expose_auth_scope`. Both flags gate
# both `Scopes::ALL` membership AND the registration of the gated tools
# in the MCP server tool registry. Defense-in-depth per the master
# agent's locked decision.
#
# Tier shape: `Scopes.all` (method) recomputes from the live config flag,
# while `Scopes::ALL` (constant) is captured at boot — Doorkeeper's
# initializer reads the constant directly because initializers run
# before the autoloader is fully wired. Both views agree as long as the
# environment file (production/development/test) has set the flag
# before this file is loaded, which is the case for all three.
module Scopes
  DEV  = "dev"
  APP  = "app"
  AUTH = "auth"

  DESCRIPTIONS = {
    DEV  => "read and capture developer docs.",
    APP  => "application access. manage channels, videos, projects, and the calendar.",
    AUTH => "auth + login security. list pending attempts, approve / block / unblock / purge, read the audit log."
  }.freeze

  # Recompute the catalog from the live config flag. Used by callers
  # that read the value at runtime (specs that stub the flag, the MCP
  # server's tool-registry gate).
  def self.all
    base = [ APP ]
    base.unshift(DEV)   if dev_exposed?
    base << AUTH        if auth_exposed?
    base.freeze
  end

  # Returns the live value of the `dev` strip-on-release flag. Centralised
  # so specs can stub one place. Defaults to `true` if the configuration
  # hasn't been set yet (defensive — every environment file sets it
  # explicitly).
  def self.dev_exposed?
    return true unless Rails.application.config.x.respond_to?(:mcp)
    flag = Rails.application.config.x.mcp&.expose_dev_scope
    flag.nil? ? true : flag
  end

  # Returns the live value of the `auth` strip-on-release flag. Mirrors
  # `dev_exposed?`. Defaults to `true` if unset so the test environment
  # picks up the scope without explicit opt-in (every environment file
  # still sets it explicitly).
  def self.auth_exposed?
    return true unless Rails.application.config.x.respond_to?(:mcp)
    flag = Rails.application.config.x.mcp&.expose_auth_scope
    flag.nil? ? true : flag
  end

  # Frozen array captured at boot. Doorkeeper's initializer reads this
  # constant directly because initializers can run before the
  # autoloader is fully wired.
  ALL = all
end
