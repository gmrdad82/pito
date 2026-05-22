# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::AppVersionComponent, type: :component do
  subject(:component) { described_class.new }

  let(:version) { Rails.root.join("VERSION").read.strip }
  let(:expected_url) { "https://github.com/gmrdad82/pito/releases/tag/v#{version}" }

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  it "renders the version string from the VERSION file" do
    render_inline(component)
    expect(page).to have_text(version)
  end

  it "renders a link to the GitHub release tag for the current version" do
    render_inline(component)
    expect(page).to have_css("a.sb-version[href='#{expected_url}']")
  end

  it "opens the link in a new tab" do
    render_inline(component)
    expect(page).to have_css("a[target='_blank']")
  end

  it "includes rel=noopener noreferrer on the link" do
    render_inline(component)
    expect(page).to have_css("a[rel='noopener noreferrer']")
  end

  it "exposes the release_url via the i18n key, not hardcoded" do
    expect(component.release_url).to eq(expected_url)
  end
end
