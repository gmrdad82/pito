require "rails_helper"

# End-to-end happy path: `[+]` on /channels → land on the Google
# connection manage page → tick two channels in the multi-select form
# → submit → redirect back to /channels with both channels visible.
#
# This is the critical user journey for the URL-paste drop. Failure
# anywhere on this path strands a freshly-installed pito instance
# with no way to add channels at all.
RSpec.describe "Add channels via Google", type: :system do
  let(:user) { User.first || create(:user) }
  let!(:connection) do
    create(:youtube_connection, user: user, email: "u@example.test")
  end

  before do
    driven_by(:rack_test)

    # Stub the YouTube API so the manage page renders a deterministic
    # set of channels under `mine: true`. The same stub serves the
    # initial GET and any subsequent re-render.
    allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
      items: [
        { id: "UCaaaaaaaaaaaaaaaaaaaaaa",
          snippet: { title: "Alpha Channel" },
          statistics: { subscriber_count: 1234 } },
        { id: "UCbbbbbbbbbbbbbbbbbbbbbb",
          snippet: { title: "Beta Channel" },
          statistics: { subscriber_count: 56 } }
      ],
      next_page_token: nil
    )
  end

  it "routes [+] on /channels to /settings/youtube, picks 2 channels, lists them on /channels" do
    visit channels_path

    # `[+]` on the picker is the canonical entry point.
    click_link "[+]"
    expect(page).to have_current_path(settings_youtube_path)
    expect(page).to have_content("Google connection")
    expect(page).to have_content("select channels to add")

    # The two stubbed channels render with enabled checkboxes.
    expect(page).to have_content("Alpha Channel")
    expect(page).to have_content("Beta Channel")

    # Tick both and submit.
    check option: "UCaaaaaaaaaaaaaaaaaaaaaa"
    check option: "UCbbbbbbbbbbbbbbbbbbbbbb"

    expect {
      click_button "[add channels]"
    }.to change { Channel.count }.by(2)

    # Submit lands on /channels with both rows now visible in the table.
    # The picker's URL column server-side middle-truncates to
    # `https://…<tail-8>`, so we match on the tail fragments rather
    # than the full UC id.
    expect(page).to have_current_path(channels_path)
    expect(page).to have_content("2 channels added.")
    expect(page).to have_content("aaaaaaaa")
    expect(page).to have_content("bbbbbbbb")
  end
end
