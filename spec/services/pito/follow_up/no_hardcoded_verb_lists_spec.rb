# frozen_string_literal: true

require "rails_helper"

# Guard: follow-up reply availability is driven by verbs.yml (the Matrix, via the
# config-driven `declared?` gate in Pito::FollowUp::Handler) — NEVER by a hardcoded
# verb allowlist inside a handler.
#
# A literal `%w[…].include?(action)` / `%i[…].include?(action)` in a handler is the
# exact drift that silently shadowed `game` (and channels/similar/vids/games/shinies)
# on the detail cards: the list fell out of sync with verbs.yml and rejected verbs
# the config declared. This spec fails the build if that anti-pattern comes back, so
# the fix can't quietly regress.
#
# Behaviour branches on a single verb (`action == "analyze"`, `when "footage"`) are
# fine — they route a declared verb to bespoke handling; they can't shadow anything
# because the gate already rejected undeclared verbs. Only inline *lists* are banned.
RSpec.describe "follow-up handlers: verbs.yml drives availability (no hardcoded lists)" do
  handler_dir   = Rails.root.join("app/services/pito/follow_up/handlers")
  handler_files = Dir[handler_dir.join("*.rb")].sort

  # `%w[a b c].include?(action)` or `%i[…].include?(action)` — an inline verb
  # allowlist gating on the parsed action token.
  FORBIDDEN_LIST_GATE = /%[wi]\[[^\]]*\]\s*\.include\?\(\s*action\s*\)/

  it "finds handler files to scan (sanity)" do
    expect(handler_files).not_to be_empty
  end

  handler_files.each do |file|
    name = File.basename(file)

    it "#{name} gates availability via verbs.yml, not an inline %w[...].include?(action) list" do
      source = File.read(file)
      expect(source).not_to match(FORBIDDEN_LIST_GATE),
        "#{name} rejects replies with a hardcoded verb list. Use the config-driven " \
        "`declared?(action)` / `undeclared_action(action)` gate (Pito::FollowUp::Handler) " \
        "so verbs.yml stays the single source of truth for reply availability."
    end
  end
end
