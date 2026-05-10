require "rails_helper"

RSpec.describe NotificationFormatter::Templates::GameReleaseUpcoming do
  let(:payload) do
    {
      "game_id"      => 99,
      "game_title"   => "Hollow Knight: Silksong",
      "release_date" => "2026-09-01",
      "days_until"   => 7,
      "igdb_url"     => "https://igdb.com/games/silksong",
      "platforms"    => %w[Windows macOS Switch]
    }
  end
  let(:notification) do
    create(:notification, :game_release_upcoming, event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is plural `days` when days_until > 1" do
      expect(template.title).to eq("Hollow Knight: Silksong releases in 7 days")
    end

    it "is singular `day` when days_until == 1" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.merge("days_until" => 1))
      expect(described_class.new(n).title).to eq("Hollow Knight: Silksong releases in 1 day")
    end

    it "handles a string days_until" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.merge("days_until" => "3"))
      expect(described_class.new(n).title).to eq("Hollow Knight: Silksong releases in 3 days")
    end

    it "falls back to `releases soon` when days_until is missing" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.except("days_until"))
      expect(described_class.new(n).title).to eq("Hollow Knight: Silksong releases soon")
    end
  end

  describe "#body" do
    it "mentions the title, platforms and humanized date" do
      body = template.body
      expect(body).to include("Hollow Knight: Silksong")
      expect(body).to include("Windows, macOS, Switch")
      expect(body).to match(/Sep 1, 2026/)
    end

    it "appends the IGDB markdown link" do
      expect(template.body).to include("[igdb](https://igdb.com/games/silksong)")
    end

    it "omits the IGDB link when nil" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.merge("igdb_url" => nil))
      expect(described_class.new(n).body).not_to include("igdb")
    end

    it "uses `tbd` when platforms is missing" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.merge("platforms" => nil))
      expect(described_class.new(n).body).to include("on tbd")
    end

    it "tolerates a non-iso release_date by passing it through" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.merge("release_date" => "Q3 2026"))
      expect(described_class.new(n).body).to include("Q3 2026")
    end
  end

  describe "#url" do
    it "is /games/<id>" do
      expect(template.url).to eq("/games/99")
    end

    it "is nil when game_id is missing" do
      n = create(:notification, :game_release_upcoming,
                 event_payload: payload.except("game_id"))
      expect(described_class.new(n).url).to be_nil
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :game_release_upcoming, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
