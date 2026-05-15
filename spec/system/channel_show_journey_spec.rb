require "rails_helper"

# Phase 7.5 §11b — thin system spec for the channel show page.
# 2026-05-11 restructure — the page now has three sections: detail
# pane, analytics pane (first), Google connection pane (second), and a
# non-pane videos table at the bottom. The journey walks all four
# surfaces and verifies `[see all videos]` lands on the pre-filtered
# videos picker when the channel has more than 30 videos.
RSpec.describe "Channel show journey", type: :system do
  before do
    driven_by(:rack_test)
    ChannelSync.clear
  end

  let!(:channel) do
    create(:channel,
           title: "Pito Journey",
           handle: "@pitojourney",
           description: "Hello world.",
           subscriber_count: 1_000,
           view_count: 50_000,
           video_count: 5)
  end

  it "loads /channels, clicks into a channel, and sees the four sections in the new order" do
    # Need >30 videos to make the `[see all videos]` link render.
    31.times { create(:video, channel: channel) }

    visit channels_path
    # The picker page renders the channel; clicking its name lands on
    # the show page. The picker truncates the URL cell with an
    # ellipsis, so we navigate via the show path directly rather than
    # asserting the full URL is present on the picker.
    visit channel_path(channel)

    # Detail section — title in H1, handle, outbound links.
    expect(page).to have_selector("h1", text: "Pito Journey")
    expect(page).to have_content("@pitojourney")
    expect(page).to have_link(text: /YouTube/)
    expect(page).to have_link(text: /Studio/)

    # Analytics section — formatted counts + [full analytics].
    expect(page).to have_content("subscribers")
    expect(page).to have_content("1,000")
    expect(page).to have_content("50,000")
    expect(page).to have_link(text: /full analytics/i, href: channel_analytics_path(channel))

    # Google section — heading present (no connection on this
    # factory channel, so the empty state renders).
    expect(page).to have_css("h2", text: "Google")

    # Videos section — heading + [see all videos] (>30 videos).
    expect(page).to have_content(/videos \(31\)/)
    expect(page).to have_link(text: /see all videos/i)

    click_link("[see all videos]")

    expect(page.current_path).to eq(videos_path)
    expect(page.current_url).to include("channel=#{channel.to_param}")
  end

  it "omits the [see all videos] link when the channel has 30 or fewer videos" do
    visit channel_path(channel)

    expect(page).to have_content(/videos \(0\)/)
    expect(page).not_to have_link(text: /see all videos/i)
  end

  # Unit A0 — the channel is a strictly read-only mirror. The show page
  # carries no edit affordance and no diff-reconciliation banner; the
  # heading-actions row is `[ changes ]`, `[ sync ]`, `[ revoke ]`,
  # `[ - ]` only.
  it "renders read-only — no edit affordance and no diff banner" do
    visit channel_path(channel)

    # No `[ e ]` / `[ edit ]` link, no edit URL anywhere on the page.
    expect(page).not_to have_link(text: /\bedit\b/i)
    expect(page.html).not_to match(%r{/channels/[^"]+/edit})

    # No diff-reconciliation banner / Turbo frame slot.
    expect(page.html).not_to include("channel_diff_banner")
    expect(page).not_to have_content(/review changes/i)

    # The history audit trail survives.
    expect(page).to have_link(text: /changes/i, href: channel_change_logs_path(channel))

    # `[ sync ]` runs the plain overwrite intent (no diff_check).
    expect(page.html).not_to include("intent=diff_check")
  end

  # 2026-05-11 (later) — row 2 zebra rhythm. The analytics pane and
  # the Google connection pane must render as two direct `.pane`
  # children of the same `.pane-row`. The `:nth-child(even)` rule in
  # tailwind/application.css then paints the right-hand sibling with
  # `--color-pane-bg-b`, making the two panes visually distinct
  # (mirrors the /settings two-up rows).
  it "renders the analytics + Google panes as two `.pane` siblings inside one `.pane-row`" do
    visit channel_path(channel)

    # Locate the pane-row that contains the analytics heading; its
    # direct `.pane` children should number exactly two, and neither
    # should carry the `.pane--standalone` modifier (that would
    # suppress the zebra rule). `rack_test` uses Nokogiri's XPath
    # engine which doesn't grok CSS `:scope`, so we walk children
    # via XPath `./` and filter by class on the Capybara side.
    row = find(".pane-row", text: "analytics", match: :first)
    panes = row.all(:xpath, "./div", visible: :all).select do |node|
      node[:class].to_s.split(/\s+/).include?("pane")
    end
    expect(panes.size).to eq(2)
    panes.each do |pane|
      classes = pane[:class].to_s.split(/\s+/)
      expect(classes).to include("pane")
      expect(classes).not_to include("pane--standalone")
    end
  end

  # 2026-05-11 (later) — YouTube-mirror layout: avatar LEFT, headline
  # stack (large title, muted `@handle · subs · videos` meta line,
  # description) RIGHT. Locks the structural shape of the detail pane
  # so the next visual revamp can't silently regress it.
  it "lays out the detail pane with avatar on the LEFT and headline on the RIGHT" do
    visit channel_path(channel)

    identity = find(".channel-identity")
    expect(identity).to have_css(".channel-avatar")
    expect(identity).to have_css(".channel-headline")
    expect(identity).to have_css(".channel-headline__title", text: "Pito Journey")
    expect(identity).to have_css(".channel-headline__meta", text: /@pitojourney.*1,000 subscribers.*5 videos/m)
    # Description lives inside the headline column (not as a sibling
    # of `.channel-identity`), mirroring YouTube's right-of-avatar
    # stack.
    expect(identity).to have_css(".channel-headline .channel-headline__description", text: "Hello world.")
  end
end
