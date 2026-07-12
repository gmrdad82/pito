# frozen_string_literal: true

require "rails_helper"

# Phase D — slash verb recognition. For EVERY slash grammar verb (canonical +
# alias), the dispatcher resolves the canonical verb, routes to :slash, and
# reports the correct auth tier. Unknown slash commands are flagged. Pure: no DB.
RSpec.describe "Dispatch — slash verb recognition", type: :dispatch do
  SLASH_SPECS = Pito::Grammar::Registry.specs(namespace: :slash).freeze

  describe "canonical + alias tokens resolve to the canonical verb + auth tier" do
    SLASH_SPECS.each do |spec|
      ([ spec.name ] + Array(spec.aliases)).each do |token|
        it "/#{token} → verb #{spec.name}, auth #{spec.auth}" do
          intent = parsed_intent("/#{token} some args")
          expect(intent[:stack]).to eq(:slash)
          expect(intent[:tool]).to eq(spec.name)
          expect(intent[:auth]).to eq(spec.auth)
          expect(intent[:known]).to be(true)
        end
      end
    end
  end

  describe "auth tiers" do
    it "login (and its /authenticate alias) is unauthenticated_only" do
      expect(parsed_intent("/login 123456")[:auth]).to eq(:unauthenticated_only)
      expect(parsed_intent("/authenticate 123456")[:auth]).to eq(:unauthenticated_only)
      expect(parsed_intent("/authenticate 123456")[:tool]).to eq(:login)
    end

    # The grammar-recognized authenticated-only verbs.
    %w[config jobs rename disconnect games logout connect new resume].each do |verb|
      it "/#{verb} is authenticated_only" do
        expect(parsed_intent("/#{verb}")[:auth]).to eq(:authenticated_only)
      end
    end

    # /theme (handler verb :themes) is mostly CLIENT-SIDE — it opens the sidebar
    # for further actions — so by design it lives in the slash handler registry,
    # not the grammar recognition/suggestion layer.
    it "/theme routes via the handler registry (client-side sidebar), not grammar recognition" do
      expect(parsed_intent("/theme")[:known]).to be(false)
      expect(Pito::Slash::Registry.lookup(:themes)).to eq(Pito::Slash::Handlers::Theme)
    end

    # /notifications is the CANONICAL recognized verb (owner-decided: shown in the
    # palette); /notifs is its alias. Both dispatch via the handler registry.
    it "/notifications is grammar-recognized (canonical) with /notifs as an alias" do
      expect(parsed_intent("/notifications")[:known]).to be(true)
      expect(parsed_intent("/notifs")[:tool]).to eq(:notifications)
      expect(Pito::Slash::Registry.lookup(:notifications)).to eq(Pito::Slash::Handlers::Notifications)
      expect(Pito::Slash::Registry.lookup(:notifs)).to eq(Pito::Slash::Handlers::Notifications)
    end
  end

  describe "unknown slash commands" do
    [ "/bogus", "/florp arg", "/xyzzy", "/" ].each do |input|
      it "#{input.inspect} → stack :slash, known: false" do
        expect(parsed_intent(input)).to include(stack: :slash, known: false)
      end
    end
  end
end
