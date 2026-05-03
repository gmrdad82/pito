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

  it "does NOT emit data-turbo-confirm even when confirm: is passed (deprecated)" do
    render_inline(described_class.new(label: "delete", href: "/items/1", confirm: "are you sure?"))
    expect(page).to have_no_css("a[data-turbo-confirm]")
  end

  it "passes through custom data attributes" do
    render_inline(described_class.new(label: "act", href: "/x", data: { action: "click->ctrl#do" }))
    expect(page).to have_css('a[data-action="click->ctrl#do"]')
  end

  it "combines destructive and method without emitting data-turbo-confirm" do
    render_inline(described_class.new(
      label: "destroy", href: "/items/1",
      destructive: true, method: :delete, confirm: "really?"
    ))
    expect(page).to have_css('a.text-danger[data-turbo-method="delete"]')
    expect(page).to have_no_css("a[data-turbo-confirm]")
  end
end
