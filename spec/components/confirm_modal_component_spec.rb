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
    # Default confirm label collapsed from "delete" to "-" as part of the
    # site-wide bracket-link relabel pass.
    expect(page).to have_css('button[type="submit"]', text: "-")
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

  # 2026-05-18 — `turbo:` kwarg. Defaults to `false` so historical
  # callers keep their full-page submit semantics. Callers that opt in
  # (`turbo: true`) want the controller's `format.turbo_stream` branch
  # to fire, so the form must NOT carry `data-turbo="false"`.
  describe "turbo: kwarg" do
    it "defaults to turbo: false — form carries data-turbo=\"false\"" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete
      ))

      expect(page).to have_css('form[data-turbo="false"]')
    end

    it "with turbo: true, form does NOT carry data-turbo=\"false\"" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete,
        turbo: true
      ))

      expect(page).to have_no_css('form[data-turbo="false"]')
    end
  end

  # Label defaults + overrides. Confirm collapses to "-" (the
  # bracket-link relabel pass); cancel reads "cancel" by default. Both
  # accept caller-supplied overrides.
  describe "labels" do
    it "uses '-' as the default confirm label" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete
      ))

      expect(page).to have_css('button[type="submit"]', text: "-")
    end

    it "uses 'cancel' as the default cancel label" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete
      ))

      expect(page).to have_css('button[type="button"]', text: "cancel")
    end

    it "honors a custom confirm_label override" do
      render_inline(described_class.new(
        id: "confirm-x", title: "save?",
        confirm_path: "/things/1", confirm_method: :post,
        confirm_label: "save now", destructive: false
      ))

      expect(page).to have_css('button[type="submit"]', text: "save now")
    end

    it "honors a custom cancel_label override" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete,
        cancel_label: "nevermind"
      ))

      expect(page).to have_css('button[type="button"]', text: "nevermind")
    end
  end

  # Custom title + body — title always renders, body renders only when
  # supplied (covered above for nil; here we sanity check non-trivial
  # markup-safe content).
  describe "title + body" do
    it "renders the supplied title text in the dialog-title slot" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete soulslikes bundle?",
        confirm_path: "/bundles/42", confirm_method: :delete
      ))

      expect(page).to have_css(".dialog-title", text: "delete soulslikes bundle?")
    end

    it "renders the supplied body text in the dialog-message slot" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        body: "members will be unlinked.",
        confirm_path: "/bundles/42", confirm_method: :delete
      ))

      expect(page).to have_css(".dialog-message", text: "members will be unlinked.")
    end
  end

  # Action style — `destructive: true` (default) gives the confirm
  # button the danger color stop; `destructive: false` keeps it
  # neutral. Cancel is always muted, regardless.
  describe "action style" do
    it "applies text-danger to the confirm button by default (destructive: true)" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete
      ))

      expect(page).to have_css('button[type="submit"].bracketed.text-danger')
    end

    it "omits text-danger on the confirm button when destructive: false" do
      render_inline(described_class.new(
        id: "confirm-x", title: "save?",
        confirm_path: "/things/1", confirm_method: :post,
        destructive: false
      ))

      expect(page).to have_css('button[type="submit"].bracketed')
      expect(page).to have_no_css('button[type="submit"].text-danger')
    end

    it "always renders cancel as a muted bracketed button" do
      render_inline(described_class.new(
        id: "confirm-x", title: "delete?",
        confirm_path: "/things/1", confirm_method: :delete
      ))

      expect(page).to have_css('button[type="button"].bracketed.text-muted', text: "cancel")
    end
  end
end
