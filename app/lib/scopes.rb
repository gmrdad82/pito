# Phase 3 — Step B (5b-token-and-auth-concern.md) — Beta scope catalog.
#
# Single source of truth for token scopes across the entire stack. The
# Settings UI (Step C) renders checkboxes from `DESCRIPTIONS`; the auth
# concern accepts only entries from `ALL`; every MCP tool's `call` method
# names one of these constants in `require_scope!`.
#
# Naming pattern: `<namespace>:<permission>`. Three namespaces are live in
# Phase 3:
#   - `dev:*`     — dev knowledge base (docs/, notes)
#   - `project:*` — project workspace (projects, collections, games,
#                   footages, notes, timelines)
#   - `yt:*`      — YouTube channels / videos / dashboards. The `yt:*`
#                   tools exist; scope enforcement on them ships now.
#
# `website:*` is declared for Phase 6 (no tools yet). Adding it now means
# the catalog is ready when Phase 6 lands.
module Scopes
  DEV_READ        = "dev:read"
  DEV_WRITE       = "dev:write"
  YT_READ         = "yt:read"
  YT_WRITE        = "yt:write"
  YT_DESTRUCTIVE  = "yt:destructive"
  WEBSITE_READ    = "website:read"
  WEBSITE_WRITE   = "website:write"
  PROJECT_READ    = "project:read"
  PROJECT_WRITE   = "project:write"

  ALL = [
    DEV_READ, DEV_WRITE,
    YT_READ, YT_WRITE, YT_DESTRUCTIVE,
    WEBSITE_READ, WEBSITE_WRITE,
    PROJECT_READ, PROJECT_WRITE
  ].freeze

  DESCRIPTIONS = {
    DEV_READ       => "Read dev knowledge base (docs/).",
    DEV_WRITE      => "Write notes to docs/notes/.",
    YT_READ        => "Read channels, videos, stats, dashboards.",
    YT_WRITE       => "Create / update channels, videos, saved views.",
    YT_DESTRUCTIVE => "Delete channels, videos, bulk-delete operations.",
    WEBSITE_READ   => "Read landing-page content (Phase 6+).",
    WEBSITE_WRITE  => "Edit landing-page content (Phase 6+).",
    PROJECT_READ   => "Read projects, collections, games, footage, notes.",
    PROJECT_WRITE  => "Create / update / delete project workspace records."
  }.freeze
end
