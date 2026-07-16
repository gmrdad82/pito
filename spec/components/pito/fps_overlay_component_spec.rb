# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FpsOverlayComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new) }

  it "hides by default" do
    expect(rendered.css(".pito-fps-overlay.hidden")).to be_present
  end

  it "keeps the fx meter span id so pito:fx:fps events still feed it" do
    expect(rendered.css("span#pito-fx-fps.tabular-nums")).to be_present
  end

  it "mounts both Stimulus identifiers (toggle wrapper + sampler span)" do
    expect(rendered.css('[data-controller="pito--fps-overlay"]')).to be_present
    expect(rendered.css('span[data-controller="pito--fx-fps"]')).to be_present
  end
end
