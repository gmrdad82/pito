require "rails_helper"

RSpec.describe ConfirmModalComponent, type: :component do
  it "renders a dialog with the given id and title" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete this thing?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_css('dialog#confirm-x.confirm-modal')
    expect(page).to have_css('dialog[data-controller="confirm-modal"]')
    expect(page).to have_text("delete this thing?")
  end

  it "renders a form posting to confirm_path with the given method" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_css('form[action="/things/1"]')
    expect(page).to have_css('form input[name="_method"][value="delete"]', visible: :all)
  end

  it "renders a destructive confirm button by default" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_css('button[type="submit"].bracketed.text-danger')
    expect(page).to have_css('button[type="submit"]', text: "delete")
  end

  it "renders a non-destructive confirm button when destructive: false" do
    render_inline(described_class.new(
      id: "confirm-x", title: "save?",
      confirm_path: "/things/1", confirm_method: :post,
      confirm_label: "save", destructive: false
    ))

    expect(page).to have_css('button[type="submit"].bracketed')
    expect(page).to have_no_css('button[type="submit"].text-danger')
  end

  it "renders a cancel button wired to confirm-modal#close" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_css('button[type="button"][data-action="confirm-modal#close"]', text: "cancel")
  end

  it "renders the optional body when provided" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      body: "this cannot be undone.",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_text("this cannot be undone.")
  end

  it "omits the body when nil" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_no_css(".dialog-message")
  end

  it "does not emit data-turbo-confirm anywhere" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_no_css("[data-turbo-confirm]")
  end

  it "disables Turbo on the form so the DELETE submits as a real request" do
    render_inline(described_class.new(
      id: "confirm-x", title: "delete?",
      confirm_path: "/things/1", confirm_method: :delete
    ))

    expect(page).to have_css('form[data-turbo="false"]')
  end
end
