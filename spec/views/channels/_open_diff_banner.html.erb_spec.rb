require "rails_helper"

# Audit 2026-05-12 — Turbo Frame "Content missing" sweep.
#
# The `_open_diff_banner` partial renders into a `channel_diff_banner`
# Turbo Frame on the channel show page (and via Turbo Stream from the
# diff-check job). The `[review changes]` link inside the banner must
# carry `data-turbo-frame="_top"`; otherwise Turbo scopes the click to
# the enclosing frame, fetches `/channels/:slug/diff` (a full-page
# response with no matching frame), and shows "Content missing" inside
# the banner instead of navigating the document.
RSpec.describe "channels/_open_diff_banner.html.erb", type: :view do
  let(:channel) { build_stubbed(:channel) }
  let(:diff) do
    instance_double(ChannelDiff,
                    fields: { "title" => { "pito" => "a", "youtube" => "b" } })
  end

  it "wraps the body in the channel_diff_banner Turbo Frame" do
    render "channels/open_diff_banner", channel: channel, diff: diff
    expect(rendered).to match(/<turbo-frame[^>]*id="channel_diff_banner"/)
  end

  it "renders the `[ review changes ]` link" do
    render "channels/open_diff_banner", channel: channel, diff: diff
    expect(rendered).to include("review changes")
  end

  it "marks `[ review changes ]` as `data-turbo-frame=\"_top\"` " \
     "so the link breaks out of the enclosing banner frame on click " \
     "(otherwise Turbo would render 'Content missing' against the " \
     "frame-less diff page)" do
    render "channels/open_diff_banner", channel: channel, diff: diff
    review_anchor = rendered[/<a [^>]*href="#{Regexp.escape(Rails.application.routes.url_helpers.diff_channel_path(channel))}"[^>]*>/]
    expect(review_anchor).not_to be_nil,
      "expected to find a `[review changes]` anchor in the rendered banner"
    expect(review_anchor).to include('data-turbo-frame="_top"')
  end
end
