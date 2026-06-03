# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ChannelTitleComponent do
  it "renders title in bold quotes" do
    node = render_inline(described_class.new("Manfy Plays Hard Games"))
    expect(node.text).to eq('"Manfy Plays Hard Games"')
    expect(node.css("span.font-bold")).to be_present
  end

  it "renders nothing when title is blank" do
    node = render_inline(described_class.new(""))
    expect(node.text).to be_blank
  end

  it "renders nothing when title is nil" do
    node = render_inline(described_class.new(nil))
    expect(node.text).to be_blank
  end
end
