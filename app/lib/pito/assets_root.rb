# Phase 7.5 §05 — `pito-assets` volume helper.
#
# Resolves absolute Pathnames under the Pito-managed assets root. The root
# is the on-disk home for Pito-derived binary assets (Active Storage's
# `:local` service, footage thumbnails, future channel banners / video
# thumbnails). It is NOT a copy of source footage — `Footage#local_path`
# continues to point at the user's drive.
#
# The assets root resolves from `ENV["PITO_ASSETS_PATH"]` and defaults to
# `/var/lib/pito-assets` (matching `config/storage.yml` and the production
# Hetzner mount point). A relative env value (e.g. `tmp/pito-assets` in the
# committed `.env.example`) is anchored to `Rails.root` so dev runs stay
# inside the repo tree without root permissions.
#
# Mirrors the path-safety semantics of `DevDocPath`: validation is purely
# lexical (`Pathname#cleanpath`) and traversal is rejected before any
# filesystem touch. Active Storage manages its own internal layout under
# `<root>/active_storage/...`; tenant-scoped consumers (footage thumbnails,
# future per-tenant assets) use `tenant_root(tenant)` for the
# `<root>/<tenant_id>/` shape.
module Pito
  module AssetsRoot
    DEFAULT_ROOT = "/var/lib/pito-assets"

    module_function

    # Return the absolute Pathname for the assets root. Reads
    # `PITO_ASSETS_PATH` with `DEFAULT_ROOT` as fallback. Relative values
    # (committed in `.env.example` for the dev workflow) anchor to
    # `Rails.root` so the resolved path is always absolute.
    def root
      raw = ENV.fetch("PITO_ASSETS_PATH", DEFAULT_ROOT).to_s
      pathname = Pathname.new(raw)
      pathname = Rails.root.join(raw) if pathname.relative?
      pathname.cleanpath
    end

    # Return an absolute Pathname under the assets root for `segments`.
    # All inputs are joined under `root` and validated with cleanpath
    # containment so `..` traversal cannot escape. Raises
    # `Pito::AssetsRoot::Error` on absolute or escaping input.
    def path(*segments)
      raise Error, "at least one segment is required" if segments.empty?

      segments.each do |segment|
        raw = segment.to_s
        raise Error, "segment must not be empty" if raw.strip.empty?
        raise Error, "segment must be relative (no leading '/')" if raw.start_with?("/")
      end

      base = root
      candidate = base.join(*segments.map(&:to_s)).cleanpath

      unless inside?(candidate, base)
        raise Error, "path escapes assets root: #{candidate}"
      end

      candidate
    end

    # `mkdir_p` shorthand. Resolves `path(*segments)` and ensures the
    # directory exists (and every intermediate parent). Idempotent.
    # Returns the resolved Pathname.
    def ensure_dir!(*segments)
      target = path(*segments)
      FileUtils.mkdir_p(target)
      target
    end

    # Tenant-scoped subdirectory. Returns `<root>/<tenant_id>/`. The
    # directory is created if it does not exist so callers can write
    # immediately. Mirrors the `<root>/<tenant_id>/` shape the notes
    # surface uses under `PITO_NOTES_PATH`.
    def tenant_root(tenant)
      raise Error, "tenant is required" if tenant.nil?
      raise Error, "tenant must respond to #id" unless tenant.respond_to?(:id)
      raise Error, "tenant id is required" if tenant.id.nil?

      ensure_dir!(tenant.id.to_s)
    end

    # True if `candidate` is exactly `base` or any descendant. Both
    # arguments must be cleanpath'd absolute Pathnames.
    def inside?(candidate, base)
      return false unless candidate.absolute? && base.absolute?
      return true if candidate == base

      candidate_parts = candidate.to_s.split("/")
      base_parts = base.to_s.split("/")
      return false if candidate_parts.length <= base_parts.length

      candidate_parts.first(base_parts.length) == base_parts
    end

    class Error < StandardError; end
  end
end
