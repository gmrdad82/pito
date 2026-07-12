# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ChatboxHint do
  describe ".sample" do
    it "returns the login example when unauthenticated" do
      expect(described_class.sample(authenticated: false))
        .to eq(I18n.t("pito.shell.chatbox.hints.login"))
    end

    it "returns an implemented-command example when authenticated" do
      hint = described_class.sample(authenticated: true)
      expected = described_class::AUTHENTICATED_HINTS
                   .map { |k| I18n.t("pito.shell.chatbox.hints.#{k}") }
      expect(expected).to include(hint)
    end

    it "samples /help today (the only implemented authenticated hint)" do
      expect(described_class.sample(authenticated: true))
        .to eq(I18n.t("pito.shell.chatbox.hints.help"))
    end
  end
end
