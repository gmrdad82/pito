# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::ManPage do
  subject(:rendered) do
    described_class.render(
      usage: "verb <arg> [option]",
      groups: [
        [ "Options:",
          [
            [ "with <columns>",  "Append columns" ],
            [ "--help",          "Print help"     ]
          ]
        ],
        [ "Arguments:",
          [
            [ "platform, platforms", "PlayStation / Switch / Steam" ]
          ]
        ]
      ]
    )
  end

  it "wraps the output in .pito-help-block" do
    expect(rendered).to include('<div class="pito-help-block">')
    expect(rendered).to end_with("</div>")
  end

  it "is html_safe" do
    expect(rendered).to be_html_safe
  end

  it "renders a yellow bold Usage: header" do
    expect(rendered).to include('<span class="text-yellow font-bold">Usage:</span>')
  end

  it "renders yellow bold group headers" do
    expect(rendered).to include('<span class="text-yellow font-bold">Options:</span>')
    expect(rendered).to include('<span class="text-yellow font-bold">Arguments:</span>')
  end

  it "html-escapes the usage line and wraps it dim" do
    # < and > in the usage string must be escaped
    expect(rendered).to include("&lt;arg&gt;")
    expect(rendered).to include('<span class="text-fg-dim">')
  end

  it "renders tokens in cyan" do
    expect(rendered).to include('<span class="text-cyan">')
    expect(rendered).to include("with &lt;columns&gt;")
    expect(rendered).to include("--help")
  end

  it "renders descriptions in dim" do
    expect(rendered).to include("Append columns")
    expect(rendered).to include("Print help")
  end

  it "aligns tokens across all groups with consistent padding" do
    # The longest raw token is "platform, platforms" (19 chars).
    # GAP = 3 → width = 22.
    # "with <columns>" is 14 chars → 8 spaces of padding.
    # "--help" is 6 chars → 16 spaces of padding.
    # We verify by checking the padding for "--help" (the shortest token).
    longest_token = "platform, platforms"
    gap = 3
    width = longest_token.length + gap
    help_token_len = "--help".length
    expected_pad = " " * (width - help_token_len)
    expect(rendered).to include("--help</span>#{expected_pad}")
  end
end
