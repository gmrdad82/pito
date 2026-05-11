require "rails_helper"

# Regression for the `/channels` `[ ] starred` filter chip. The chip
# renders via `FilterChipComponent` (canonical) with `param: "star"`,
# default `value: "yes"`, and `frame: "channels-index-table"` so its
# click swaps the table frame in place. Same component drives the
# `/notifications` `[ ] unread` chip; this spec ensures the channels
# call site stays wired.
RSpec.describe "Channels filter chip", type: :system do
  before { driven_by(:rack_test) }

  it "renders the [ ] starred chip on the index" do
    create(:channel)
    visit "/channels"
    expect(page).to have_selector("a.filter-chip", text: /starred/i)
    expect(page).to have_content("[ ]")
  end

  it "click on the starred chip flips the URL to ?star=yes" do
    create(:channel)
    visit "/channels"
    find("a.filter-chip", text: /starred/i).click
    expect(page.current_url).to include("star=yes")
  end

  it "filter chip renders [x] when star=yes is active" do
    create(:channel)
    visit "/channels?star=yes"
    expect(page).to have_selector("a.filter-chip .md-check-static", text: "[x]")
  end

  it "?star=yes filters the index to starred channels only" do
    starred = create(:channel, :starred)
    plain   = create(:channel)
    visit "/channels?star=yes"
    expect(page.body).to include(starred.channel_url)
    expect(page.body).not_to include(plain.channel_url)
  end
end
