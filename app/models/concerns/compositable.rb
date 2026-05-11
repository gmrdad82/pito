# Phase 27 §01h — Compositable mixin.
#
# Shared interface for models that own an on-disk composite cover JPEG
# fingerprinted by `Composite::Checksum`. Currently mixed into:
#   - `Bundle`     (Phase 14 §2 — series / collection / genre / custom
#                  groupings of Games).
#   - `Collection` (Phase 27 §01h — the new sub-shelf composite covers).
#
# The mixin captures the three responsibilities that BOTH models share:
#   1. Resolve the absolute on-disk Pathname for the composite cover
#      from `composite_cover_path` (a relative path under
#      `<PITO_ASSETS_PATH>/composites/`).
#   2. Render the public URL the auth-gated `/composites/:filename.jpg`
#      controller serves.
#   3. Sweep the on-disk file when the host model is destroyed
#      (best-effort — `Errno::ENOENT` is swallowed).
#
# What it does NOT cover:
#   - Building the composite — each host has its own composer service
#     (`Composite::Builder` for Bundle, `Collections::CoverComposer` for
#     Collection). The two composers differ on member ordering,
#     fingerprint payload, layout matrix, and degradation policy; the
#     mixin would over-couple them.
#   - Membership-change hooks — Bundle wires `after_save` into
#     `BundleCoverBuild`; Collection wires `Game#after_update_commit` so
#     the eviction fires on the right side of the association.
#
# Database contract — host model MUST have both columns:
#   - `composite_cover_path`     :string (nullable) — relative path
#     under `<PITO_ASSETS_PATH>/composites/<filename>.jpg`.
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
  # not been built yet. Routes through the auth-gated
  # `/composites/:filename` controller (see `CompositesController`).
  def composite_cover_url
    return nil if composite_cover_path.blank?
    "/composites/#{File.basename(composite_cover_path)}"
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
