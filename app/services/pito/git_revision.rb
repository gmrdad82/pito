module Pito
  # FB-128 (2026-05-21) — Boot-time snapshot of the git revision the
  # running Rails process was built from. Powers the about dialog's
  # bracketed version action so `[v0.0.1.beta3]` opens the matching
  # GitHub commit in a new tab.
  #
  # Captured ONCE at boot via shell-out to `git rev-parse` against the
  # repo at `Rails.root`. Subsequent reads return the cached value — the
  # rendered commit URL is stable for the lifetime of the process, which
  # matches the deploy model (process restart on every deploy).
  #
  # Both `SHA` and `BRANCH` may be `nil` when the process boots outside
  # a git checkout (a stripped production container, an `eval`-style
  # test runner, etc.) — every caller handles the `nil` case by falling
  # back to plain unlinked text. The shell-out is wrapped in a rescue so
  # a missing `git` binary or unreadable `.git/` directory cannot raise
  # at boot.
  #
  # Repository slug is locked to `gmrdad82/pito` to match the canonical
  # GitHub remote referenced throughout the codebase (see e.g.
  # `app/controllers/footage_importer/downloads_controller.rb` for the
  # releases-API URL using the same slug).
  module GitRevision
    REPO_SLUG = "gmrdad82/pito".freeze

    SHA = begin
      out = `git -C #{Rails.root} rev-parse HEAD 2>/dev/null`.strip
      out.presence
    rescue StandardError
      nil
    end

    BRANCH = begin
      out = `git -C #{Rails.root} rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      out.presence
    rescue StandardError
      nil
    end

    def self.sha
      SHA
    end

    def self.branch
      BRANCH
    end

    # Short 7-char SHA for any future surface (status bar tail, debug
    # overlay, etc.). The about dialog itself renders the full version
    # string, not the SHA — but the helper is here for parity with the
    # CLAUDE.md "no inline literals" rule.
    def self.short_sha
      SHA&.first(7)
    end

    # Canonical GitHub commit URL for the running process, or `nil`
    # when the SHA could not be captured at boot. Callers MUST handle
    # the `nil` case (see `Tui::AboutDialogComponent#commit_url`).
    def self.commit_url
      return nil unless SHA

      "https://github.com/#{REPO_SLUG}/commit/#{SHA}"
    end
  end
end
