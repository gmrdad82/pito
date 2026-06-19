# frozen_string_literal: true

require "rails_helper"

# The PostCommandDotsComponent is the "backend working" indicator.
#
# Semantics (from design):
#   - Dots appear when a command is submitted (backend is evaluating it).
#   - Echo arriving does NOT hide the dots — it just confirms receipt.
#   - Dots disappear when the RESULT segment arrives (evaluation complete).
#   - The Braille spinner is a SEPARATE indicator for deep processing;
#     it has nothing to do with the dots.
#
# Visibility is managed by pito--dots Stimulus controller (dots_controller.js)
# via the `pito-dots--hidden` CSS class on the wrapper.
RSpec.describe Pito::Shell::PostCommandDotsComponent do
  subject(:node) { render_inline(described_class.new) }

  it "renders the pito-comet container" do
    expect(node.css("div.pito-comet")).not_to be_empty
  end

  it "renders exactly 8 dot elements (the comet animation requires 8)" do
    expect(node.css("div.pito-comet div.dot").length).to eq(8)
  end
end
