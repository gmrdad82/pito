require "rails_helper"

RSpec.describe BracketedLinkComponent, type: :component do
  it "renders a linked bracketed link" do
    render_inline(described_class.new(label: "open", href: "/channels/1"))
    expect(page).to have_link("[open]", href: "/channels/1")
    expect(page).to have_css("a.bracketed")
    expect(page).to have_css("span.bl", text: "open")
  end

  it "renders active state as bold span" do
    render_inline(described_class.new(label: "home", active: true))
    expect(page).to have_css("span", text: "[home]")
    expect(page).to have_no_css("a")
  end

  it "renders active when href is nil" do
    render_inline(described_class.new(label: "home"))
    expect(page).to have_css("span", text: "[home]")
    expect(page).to have_no_css("a")
  end

  it "renders destructive with text-danger class" do
    render_inline(described_class.new(label: "delete", href: "/items/1", destructive: true))
    expect(page).to have_css("a.text-danger")
  end

  it "includes turbo method data attribute" do
    render_inline(described_class.new(label: "delete", href: "/items/1", method: :delete))
    expect(page).to have_css('a[data-turbo-method="delete"]')
  end

  it "passes through custom data attributes" do
    render_inline(described_class.new(label: "act", href: "/x", data: { action: "click->ctrl#do" }))
    expect(page).to have_css('a[data-action="click->ctrl#do"]')
  end

  it "combines destructive and method without emitting data-turbo-confirm" do
    render_inline(described_class.new(
      label: "destroy", href: "/items/1",
      destructive: true, method: :delete
    ))
    expect(page).to have_css('a.text-danger[data-turbo-method="delete"]')
    expect(page).to have_no_css("a[data-turbo-confirm]")
  end

  # 2026-05-16 polish — external-link auto-detection.
  #
  # The component inspects `href:` and, when it is an absolute `http://`
  # or `https://` URL, automatically applies `target="_blank"` and
  # `rel="noopener noreferrer"`. Relative paths, fragment anchors,
  # `mailto:`, and `tel:` stay default (no target/rel) so internal Turbo
  # navigation, back-button history, and same-tab continuity keep working.
  # Explicit caller-passed `target:` / `rel:` always win — auto-detection
  # is the default for the unspecified case.
  describe "external-link auto-detection" do
    it "auto-applies target/rel to absolute https URLs" do
      render_inline(described_class.new(label: "steam", href: "https://store.steampowered.com/app/1/"))
      expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"]')
    end

    it "auto-applies target/rel to absolute http URLs" do
      render_inline(described_class.new(label: "legacy", href: "http://example.com/"))
      expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"]')
    end

    it "treats mixed-case scheme as external" do
      render_inline(described_class.new(label: "shout", href: "HTTPS://EXAMPLE.COM/"))
      expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"]')
    end

    it "leaves relative path hrefs without target/rel" do
      render_inline(described_class.new(label: "open", href: "/channels/1"))
      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css("a[rel]")
    end

    it "leaves fragment anchors without target/rel" do
      render_inline(described_class.new(label: "top", href: "#top"))
      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css("a[rel]")
    end

    it "leaves mailto: hrefs without target/rel" do
      render_inline(described_class.new(label: "mail", href: "mailto:hi@example.com"))
      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css("a[rel]")
    end

    it "leaves tel: hrefs without target/rel" do
      render_inline(described_class.new(label: "call", href: "tel:+15551234"))
      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css("a[rel]")
    end

    it "lets caller-supplied target override the auto-default on external hrefs" do
      render_inline(described_class.new(
        label: "inline", href: "https://example.com/", target: "_self"
      ))
      expect(page).to have_css('a[target="_self"]')
      expect(page).to have_no_css('a[target="_blank"]')
    end

    it "lets caller-supplied rel override the auto-default on external hrefs" do
      render_inline(described_class.new(
        label: "lax", href: "https://example.com/", rel: "noopener"
      ))
      expect(page).to have_css('a[rel="noopener"]')
      expect(page).to have_no_css('a[rel="noopener noreferrer"]')
    end

    it "lets caller force an external-looking URL to omit target by passing nil" do
      render_inline(described_class.new(
        label: "raw", href: "https://example.com/", target: nil, rel: nil
      ))
      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css("a[rel]")
    end

    it "lets caller force target/rel on an otherwise-internal relative href" do
      render_inline(described_class.new(
        label: "popup", href: "/something", target: "_blank", rel: "noopener noreferrer"
      ))
      expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"]')
    end
  end
end
