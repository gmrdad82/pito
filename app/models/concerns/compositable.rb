# Phase 27 §01h / Phase 27 follow-up (2026-05-17) — Compositable mixin.
#
# Shared interface for models that own an on-disk composite cover JPEG
# fingerprinted by `Composite::Checksum`. Currently mixed into:
#   - `Bundle` (Phase 14 §2 — bundle groupings of Games; the only host
#     after the 2026-05-17 Collection→Bundle consolidation).
#
# The mixin captures the three responsibilities a composite-cover host
# needs:
#   1. Resolve the absolute on-disk Pathname for the composite cover
#      from `composite_cover_path` (a relative path under
#      `<PITO_ASSETS_PATH>/covers/bundles/<id>/composite.jpg`).
#   2. Render the public URL the static-file middleware serves via the
#      `public/covers` → `<PITO_ASSETS_PATH>/covers` symlink.
#   3. Sweep the on-disk file when the host model is destroyed
#      (best-effort — `Errno::ENOENT` is swallowed).
#
# What it does NOT cover:
#   - Building the composite — the host's composer service does that
#     (`Composite::Builder` for Bundle).
#   - Membership-change hooks — Bundle wires `after_save` into
#     `BundleCoverBuild`; `BundleMember`'s `after_commit` enqueues
#     rebuilds when membership changes.
#
# 2026-05-17 unification — composites moved from
# `<PITO_ASSETS_PATH>/composites/bundle-<id>.jpg` (served by an
# auth-gated `/composites/:filename` controller) to
# `<PITO_ASSETS_PATH>/covers/bundles/<id>/composite.jpg` (served
# directly by Rails' static-file middleware via the `public/covers`
# symlink — same path the game masters at
# `covers/games/<id>/master.jpg` use). The unified `/covers/`
# namespace is the single home for every cover-art asset; the legacy
# `CompositesController` and its route were dropped in the same pass.
#
# Database contract — host model MUST have both columns:
#   - `composite_cover_path`     :string (nullable) — relative path
#     under `<PITO_ASSETS_PATH>/<...>`. The new layout writes
#     `covers/bundles/<id>/composite.jpg`; legacy rows wrote
#     `composites/bundle-<id>.jpg`. Both shapes resolve through
#     `Pito::AssetsRoot.path(*Pathname.new(path).each_filename.to_a)`.
#   - `composite_cover_checksum` :string (nullable) — 64-char hex
#     SHA-256, the fingerprint over sorted cover_image_ids + layout name.
#
# The mixin assumes the host registers its own `before_destroy` callback
# wired to `#sweep_composite_cover_file`. Hosts can override the
# concrete method (e.g. to also evict an in-memory cache) but should
# call `super` so the default `File.delete` path runs.
module Compositable
  extend ActiveSupport::Concern

  # Public URL for the composite cover. Returns nil when the host has
  # not been built yet. Served directly by the static-file middleware
  # via the `public/covers` → `<PITO_ASSETS_PATH>/covers` symlink — no
  # controller hop. Returns a leading slash plus the stored relative
  # path so a row that already lives under `covers/bundles/...` renders
  # as `/covers/bundles/.../composite.jpg`.
  def composite_cover_url
    return nil if composite_cover_path.blank?
    "/#{composite_cover_path}"
  end

  # Absolute on-disk Pathname for the composite cover. Returns nil when
  # the host has not been built yet OR when the stored relative path
  # escapes the assets root.
  def composite_cover_absolute_path
    return nil if composite_cover_path.blank?
    Pito::AssetsRoot.path(*Pathname.new(composite_cover_path).each_filename.to_a)
  rescue Pito::AssetsRoot::Error
    nil
  end

  # Best-effort cleanup. Called from the host's `before_destroy` hook.
  # Survives `Errno::ENOENT` (file already gone) and any unexpected
  # error during the delete (we never want destroy to fail because the
  # composite cache happened to be in a weird state).
  def sweep_composite_cover_file
    abs = composite_cover_absolute_path
    File.delete(abs) if abs && File.exist?(abs)
  rescue StandardError
    nil
  end
end
