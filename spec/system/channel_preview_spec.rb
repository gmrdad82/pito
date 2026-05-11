require "rails_helper"

# Phase 7.5 §11d — Channel multi-layout preview system spec.
#
# rack_test driver — does NOT execute JavaScript. We still verify
# the end-to-end Rails wiring:
#
#   * the `[preview]` bracketed link is present on the edit form
#     and carries the `modal-trigger` Stimulus binding pointing at
#     the per-channel modal id;
#   * the wide modal renders inside the edit page with all three
#     layout panels (desktop active by default);
#   * the form's editable inputs carry the
#     `data-action="input->channel-preview#updatePreview"` binding
#     plus the `data-channel-preview-field-param` attribute on
#     every editable text field (title / handle / description);
#   * navigating directly to `/channels/:id/preview?title=...`
#     returns a preview reflecting the override (this is the
#     payload the Stimulus controller hits via fetch).
RSpec.describe "Channel preview", type: :system do
  before { driven_by(:rack_test) }

  let(:channel) do
    create(:channel,
           title: "Cached Title",
           description: "Cached body.",
           subscriber_count: 999)
  end

  describe "edit page wiring" do
    it "renders a [preview] bracketed link wired to modal-trigger#open" do
      visit edit_channel_path(channel)

      expect(page).to have_link("preview")

      preview_link = find("a.bracketed", text: "preview")
      expect(preview_link["data-controller"]).to include("modal-trigger")
      expect(preview_link["data-action"]).to include("click->modal-trigger#open")
      expect(preview_link["data-modal-trigger-target-id-value"])
        .to eq("channel-preview-modal-#{channel.id}")
    end

    it "renders the wide modal dialog with the three layout panels" do
      visit edit_channel_path(channel)

      expect(page).to have_css("dialog.wide-modal##{"channel-preview-modal-#{channel.id}"}",
                               visible: :all)
      expect(page).to have_css("#preview-layout-desktop", visible: :all)
      expect(page).to have_css("#preview-layout-mobile", visible: :all)
      expect(page).to have_css("#preview-layout-tv", visible: :all)
    end

    it "marks the desktop layout active by default" do
      visit edit_channel_path(channel)

      expect(page).to have_css("#preview-layout-desktop.active", visible: :all)
      expect(page).to have_css("#preview-layout-mobile[hidden]", visible: :all)
      expect(page).to have_css("#preview-layout-tv[hidden]", visible: :all)
    end

    it "renders the [desktop][mobile][tv] top nav with [desktop] active-styled" do
      visit edit_channel_path(channel)

      expect(page).to have_css("span[data-layout='desktop'].preview-nav-active",
                               visible: :all)
      expect(page).to have_css("span[data-layout='mobile'].bracketed", visible: :all)
      expect(page).to have_css("span[data-layout='tv'].bracketed", visible: :all)
      # The non-active siblings do NOT carry the active modifier class.
      mobile = find("span[data-layout='mobile']", visible: :all)
      expect(mobile[:class]).not_to include("preview-nav-active")
    end

    it "binds the channel-preview Stimulus controller around both the form and the modal" do
      visit edit_channel_path(channel)

      wrapper = find("[data-controller='channel-preview']")
      expect(wrapper["data-channel-preview-url-value"]).to eq(channel_preview_path(channel))
      expect(wrapper["data-channel-preview-debounce-ms-value"]).to eq("300")

      # The form lives inside the controller scope so the input
      # listener sees keystrokes; the modal lives inside it too so
      # the streamed `#channel-preview` replacement target is in
      # the same scope.
      within(wrapper) do
        expect(page).to have_css("form")
        expect(page).to have_css("dialog.wide-modal", visible: :all)
      end
    end

    it "tags every editable input with the channel-preview input action" do
      visit edit_channel_path(channel)

      title = find("input#channel_title")
      expect(title["data-action"]).to include("input->channel-preview#updatePreview")
      expect(title["data-channel-preview-field-param"]).to eq("title")

      handle = find("input#channel_handle")
      expect(handle["data-action"]).to include("input->channel-preview#updatePreview")
      expect(handle["data-channel-preview-field-param"]).to eq("handle")

      description = find("textarea#channel_description")
      expect(description["data-action"]).to include("input->channel-preview#updatePreview")
      expect(description["data-channel-preview-field-param"]).to eq("description")
    end

    it "renders the modal close affordance with bracketed [close] (no JS confirm)" do
      visit edit_channel_path(channel)

      within("dialog##{"channel-preview-modal-#{channel.id}"}", visible: :all) do
        expect(page).to have_link("close", visible: :all)
      end

      expect(page.body).not_to include("data-turbo-confirm")
      expect(page.body).not_to match(/window\.confirm\(/)
      expect(page.body).not_to match(/alert\(/)
    end
  end

  describe "preview endpoint payload (what the Stimulus controller fetches)" do
    it "returns a body reflecting pending edits sent as query params" do
      visit "#{channel_preview_path(channel)}?title=Live%20Edit"

      expect(page.body).to include("Live Edit")
      expect(page.body).not_to include("Cached Title")
    end

    it "preserves the active_layout choice across re-renders" do
      visit "#{channel_preview_path(channel)}?active_layout=mobile&title=Mobile%20Test"

      expect(page.body).to include("data-active-layout=\"mobile\"")
      expect(page.body).to include("Mobile Test")
    end
  end
end
