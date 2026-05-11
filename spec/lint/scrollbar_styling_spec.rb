require "rails_helper"

# Guard spec for the sitewide themed-scrollbar rules in
# `app/assets/tailwind/application.css`. The original ruleset only
# styled horizontal scrollbars (axis-suffixed Webkit selectors and a
# per-container Firefox opt-in list); the default vertical scrollbar
# rendered as the OS chrome, visually inconsistent with the rest of
# the monospace minimalist design.
#
# The rules below must remain in place so that BOTH axes share the
# same look — 8px thumb, themed via `--color-muted` / `--color-bg`,
# both Webkit and Firefox covered globally.
RSpec.describe "themed scrollbar rules in application.css" do
  let(:css_path) do
    Rails.root.join("app/assets/tailwind/application.css")
  end
  let(:css) { File.read(css_path) }

  it "defines a global Webkit scrollbar block with both axes sized" do
    expect(css).to match(
      /::-webkit-scrollbar\s*\{[^}]*width:\s*8px;[^}]*height:\s*8px;[^}]*\}/m
    )
  end

  it "defines a themed Webkit scrollbar thumb (muted) with rounded corners" do
    expect(css).to match(
      /::-webkit-scrollbar-thumb\s*\{[^}]*background:\s*var\(--color-muted\);[^}]*border-radius:\s*4px;[^}]*\}/m
    )
  end

  it "darkens the Webkit thumb on hover to --color-text" do
    expect(css).to match(
      /::-webkit-scrollbar-thumb:hover\s*\{[^}]*background:\s*var\(--color-text\);[^}]*\}/m
    )
  end

  it "themes the Webkit scrollbar track to --color-bg" do
    expect(css).to match(
      /::-webkit-scrollbar-track\s*\{[^}]*background:\s*var\(--color-bg\);[^}]*\}/m
    )
  end

  it "applies a global Firefox scrollbar theme on html (both axes)" do
    expect(css).to match(
      /html\s*\{[^}]*scrollbar-width:\s*thin;[^}]*scrollbar-color:\s*var\(--color-muted\)\s+var\(--color-bg\);[^}]*\}/m
    )
  end
end
