require "rails_helper"

# Phase 7.5 §11g — Channel Change History JSON jbuilder spec.
#
# Asserts the wire envelope per the Phase 21 list-endpoint contract.
RSpec.describe "channels/change_logs/index.json.jbuilder", type: :view do
  let(:user)    { create(:user, username: "owner_logs") }
  let(:channel) { create(:channel) }

  let(:log_with_user) do
    create(:channel_change_log,
           channel: channel,
           changed_by_user: user,
           field: "title",
           old_value: "Old",
           new_value: "New",
           changed_at: Time.utc(2026, 5, 11, 14, 23, 0))
  end

  # The DB schema has `changed_by_user_id` NOT NULL, but the view's
  # defensive rendering for a null FK is part of the spec contract.
  # Use a stubbed in-memory record (`build`) and force the FK to nil
  # via direct attribute assignment so the jbuilder sees `nil`.
  let(:log_without_user) do
    record = build(:channel_change_log,
                   channel: channel,
                   field: "handle",
                   old_value: nil,
                   new_value: "@new",
                   changed_at: Time.utc(2026, 5, 10, 10, 0, 0))
    record.changed_by_user = nil
    record.id = 99_999
    record
  end

  before do
    assign(:channel, channel)
    assign(:page, 1)
    assign(:total_pages, 1)
    assign(:total, 2)
    assign(:per_page, 50)
    assign(:logs, [ log_with_user, log_without_user ])
  end

  let(:json) { JSON.parse(render) }

  it "carries top-level keys `changes` and `pagination`" do
    expect(json.keys).to contain_exactly("changes", "pagination")
  end

  it "renders the pagination object" do
    expect(json["pagination"]).to eq(
      "page" => 1,
      "per_page" => 50,
      "total" => 2,
      "total_pages" => 1
    )
  end

  it "renders each row with the locked key set" do
    expect(json["changes"].first.keys).to contain_exactly(
      "id", "field", "old_value", "new_value", "changed_at", "changed_by"
    )
  end

  it "encodes changed_at as ISO-8601 UTC" do
    expect(json["changes"].first["changed_at"]).to eq("2026-05-11T14:23:00Z")
  end

  it "encodes changed_by as { id, username } when the FK resolves" do
    row = json["changes"].first
    expect(row["changed_by"]).to eq("id" => user.id, "username" => user.username)
  end

  it "encodes changed_by as null when the FK is null" do
    row = json["changes"].last
    expect(row["changed_by"]).to be_nil
  end

  it "preserves nil old_value as JSON null" do
    row = json["changes"].last
    expect(row["old_value"]).to be_nil
  end

  it "carries the field and new_value as-is" do
    row = json["changes"].first
    expect(row["field"]).to eq("title")
    expect(row["new_value"]).to eq("New")
  end

  it "renders an empty changes array when @logs is empty" do
    assign(:logs, [])
    assign(:total, 0)
    expect(JSON.parse(render)["changes"]).to eq([])
  end
end
