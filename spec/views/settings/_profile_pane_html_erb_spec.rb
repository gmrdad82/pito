require "rails_helper"

# Phase 29 (settings refactor) — profile pane partial (row 1 left).
RSpec.describe "settings/_profile_pane.html.erb", type: :view do
  let(:user) { create(:user, username: "lucy") }

  before do
    assign(:user, user)
    # `Current.user` is read by the totp-modal data-value computation.
    allow(Current).to receive(:user).and_return(user)
    render partial: "settings/profile_pane"
  end

  it "renders the profile heading" do
    expect(rendered).to include("<h2>profile</h2>")
  end

  it "renders the username input pre-filled" do
    expect(rendered).to match(/name="user\[username\]"[^>]*value="lucy"/)
  end

  it "renders the four inputs in the expected order" do
    expect(rendered).to include('name="user[current_password]"')
    expect(rendered).to include('name="user[password]"')
    expect(rendered).to include('name="user[password_confirmation]"')
  end

  it "submits to /settings/user with PATCH" do
    expect(rendered).to match(/action="\/settings\/user"/)
    expect(rendered).to match(/name="_method" value="patch"/)
  end

  it "renders the [update] submit button" do
    expect(rendered).to include("[update]")
  end

  it "carries the totp-modal Stimulus controller" do
    expect(rendered).to include('data-controller="totp-modal"')
  end
end
