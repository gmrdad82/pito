require "rails_helper"

# FB-170 (2026-05-21) — V6 `:command` palette command registry spec.
# FB-178 + FB-180 (2026-05-21) — reindex commands route through the
# existing `[reindex]` confirmation flow (no parallel POST). All
# command names + hints flow through `tui.commands.*` i18n with
# canonical brand capitalization (Meilisearch, Voyage AI, Slack,
# Discord, YouTube, PostgreSQL, Redis, …).
#
# Locks:
#   * GLOBAL_COMMANDS is the always-available set; every screen lookup
#     contains every global verb.
#   * Unknown screen names fall back to GLOBAL_COMMANDS-only.
#   * The /settings screen merges Tui::ScreenCommands::Settings on top
#     of the globals (reindex Meilisearch / reindex Voyage AI / toggle
#     all notifications / etc.).
#   * Frozen GLOBAL_COMMANDS constant — drift here silently changes
#     the navigation surface.
#   * Brand names ALWAYS capitalized everywhere they appear (CLAUDE.md
#     `feedback_brand_names_always_capitalized`).
RSpec.describe Tui::CommandRegistry do
  describe "GLOBAL_COMMANDS" do
    it "is frozen" do
      expect(described_class::GLOBAL_COMMANDS).to be_frozen
    end

    it "includes every canonical navigation verb" do
      names = described_class::GLOBAL_COMMANDS.map { |c| c[:name] }
      expect(names).to include(
        "home", "channels", "games", "videos", "projects",
        "notifications", "settings", "help", "about", "logout"
      )
    end

    it "describes logout with DELETE /session" do
      logout = described_class::GLOBAL_COMMANDS.find { |c| c[:name] == "logout" }
      expect(logout[:method]).to eq(:delete)
      expect(logout[:path].call).to eq("/session")
    end

    it "wires `help` as an :open_help action" do
      help = described_class::GLOBAL_COMMANDS.find { |c| c[:name] == "help" }
      expect(help[:action]).to eq(:open_help)
    end

    it "wires `about` as an :open_about action" do
      about = described_class::GLOBAL_COMMANDS.find { |c| c[:name] == "about" }
      expect(about[:action]).to eq(:open_about)
    end
  end

  describe ".commands_for" do
    context "with an unknown screen" do
      it "returns just the GLOBAL_COMMANDS" do
        commands = described_class.commands_for("unknown_screen")
        names = commands.map { |c| c[:name] }
        expect(names).to include("home", "settings", "help", "about", "logout")
      end

      it "does not include any settings-scoped verbs" do
        commands = described_class.commands_for("unknown_screen")
        names = commands.map { |c| c[:name] }
        expect(names).not_to include("reindex Meilisearch", "reindex Voyage AI")
      end
    end

    context "with the settings screen" do
      it "merges global + settings-scoped commands" do
        commands = described_class.commands_for("settings")
        names = commands.map { |c| c[:name] }

        # globals
        expect(names).to include("home", "channels", "games", "settings",
                                 "help", "about", "logout")
        # screen-scoped
        expect(names).to include("reindex Meilisearch", "reindex Voyage AI")
      end

      it "places screen-scoped commands BEFORE the global verbs" do
        commands = described_class.commands_for("settings")
        names = commands.map { |c| c[:name] }
        meilisearch_idx = names.index("reindex Meilisearch")
        home_idx = names.index("home")
        expect(meilisearch_idx).to be < home_idx
      end

      it "includes the per-column sort verbs (asc + desc)" do
        commands = described_class.commands_for("settings")
        names = commands.map { |c| c[:name] }

        %w[device browser ip last\ seen created].each do |col|
          expect(names).to include("sort sessions by #{col} asc")
          expect(names).to include("sort sessions by #{col} desc")
        end
      end

      it "includes the webhook clear verbs" do
        commands = described_class.commands_for("settings")
        names = commands.map { |c| c[:name] }
        expect(names).to include("clear Discord webhook", "clear Slack webhook")
      end

      it "includes the notifications toggle verbs" do
        commands = described_class.commands_for("settings")
        names = commands.map { |c| c[:name] }
        expect(names).to include("toggle all notifications",
                                 "toggle daily digest")
      end

      it "returns a non-empty list" do
        commands = described_class.commands_for("settings")
        expect(commands.length).to be > 10
      end

      it "routes reindex commands through the existing [reindex] click handle (FB-178)" do
        # Reindex commands MUST NOT carry a path/method — they fire the
        # `[reindex]` button's confirmation dialog flow instead, so the
        # palette path matches the manual `[reindex]` path 1:1.
        commands = described_class.commands_for("settings")
        meili = commands.find { |c| c[:name] == "reindex Meilisearch" }
        voyage = commands.find { |c| c[:name] == "reindex Voyage AI" }

        expect(meili[:action]).to eq(:click)
        expect(meili[:target]).to eq('[data-reindex-brand="meilisearch"]')
        expect(meili[:path]).to be_nil
        expect(meili[:method]).to be_nil

        expect(voyage[:action]).to eq(:click)
        expect(voyage[:target]).to eq('[data-reindex-brand="voyage"]')
        expect(voyage[:path]).to be_nil
        expect(voyage[:method]).to be_nil
      end

      it "uses canonical brand capitalization for all command names + hints (FB-180)" do
        commands = described_class.commands_for("settings")
        all_text = commands.flat_map { |c| [ c[:name], c[:hint] ] }.compact

        # Brand names — must be capitalized when they appear.
        # Pattern → canonical (String must be contained; Regexp must match).
        brand_pattern_pairs = {
          /\bmeilisearch\b/i  => "Meilisearch",
          /\bvoyage\b/i       => "Voyage",
          /\bslack\b/i        => "Slack",
          /\bdiscord\b/i      => "Discord",
          /\byoutube\b/i      => "YouTube",
          /\bpostgres(?:ql)?\b/i => /Postgres(?:QL)?/,
          /\bredis\b/i        => "Redis",
          /\bmacos\b/i        => "macOS",
          /\bchrome\b/i       => "Chrome",
          /\blinux\b/i        => "Linux",
          /\bandroid\b/i      => "Android"
        }

        all_text.each do |text|
          brand_pattern_pairs.each do |lower_re, canonical|
            next unless text.match?(lower_re)
            if canonical.is_a?(Regexp)
              expect(text).to match(canonical),
                "Expected '#{text}' to use canonical brand capitalization #{canonical.inspect}"
            else
              expect(text).to include(canonical),
                "Expected '#{text}' to contain canonical '#{canonical}'"
            end
          end
        end
      end
    end

    it "accepts a Symbol screen name" do
      commands = described_class.commands_for(:settings)
      names = commands.map { |c| c[:name] }
      expect(names).to include("reindex Meilisearch")
    end
  end
end
