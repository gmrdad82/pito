# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CommandCatalog, type: :service do
  subject(:sections) { described_class.sections }

  it "returns an array of sections" do
    expect(sections).to be_an(Array)
    expect(sections).not_to be_empty
  end

  it "every section has a title_key and items array" do
    sections.each do |section|
      expect(section).to have_key(:title_key)
      expect(section).to have_key(:items)
      expect(section[:items]).to be_an(Array)
    end
  end

  it "every item has label_key and insert" do
    sections.flat_map { |s| s[:items] }.each do |item|
      expect(item).to have_key(:label_key), "item missing :label_key: #{item.inspect}"
      expect(item).to have_key(:insert),    "item missing :insert: #{item.inspect}"
      expect(item[:insert]).to be_a(String)
    end
  end

  it "all title_keys resolve via I18n" do
    sections.each do |section|
      expect { I18n.t(section[:title_key], raise: true) }.not_to raise_error,
        "Missing i18n key: #{section[:title_key]}"
    end
  end

  it "all item label_keys resolve via I18n" do
    sections.flat_map { |s| s[:items] }.each do |item|
      expect { I18n.t(item[:label_key], raise: true) }.not_to raise_error,
        "Missing i18n key: #{item[:label_key]}"
    end
  end

  it "includes a YouTube section with /connect" do
    yt = sections.find { |s| s[:title_key].include?("youtube") }
    expect(yt).to be_present
    expect(yt[:items].map { |i| i[:insert] }).to include("/connect")
  end

  it "includes a Config section with /config items" do
    cfg = sections.find { |s| s[:title_key].include?("config") }
    expect(cfg).to be_present
    inserts = cfg[:items].map { |i| i[:insert] }
    expect(inserts).to all(start_with("/config"))
  end

  it "includes a General section with /help and /logout (authenticated, no /login)" do
    gen = sections.find { |s| s[:title_key].include?("general") }
    expect(gen).to be_present
    inserts = gen[:items].map { |i| i[:insert] }
    expect(inserts).to include("/help")
    expect(inserts).to include("/logout")
    expect(inserts).not_to include(a_string_starting_with("/login"))
  end

  describe "auth gating" do
    it "shows ONLY /login when unauthenticated" do
      inserts = described_class.sections(authenticated: false)
                              .flat_map { |s| s[:items].map { |i| i[:insert] } }
      expect(inserts.size).to eq(1)
      expect(inserts.first).to start_with("/login")
    end

    it "excludes /login from the authenticated palette" do
      inserts = described_class.sections(authenticated: true)
                              .flat_map { |s| s[:items].map { |i| i[:insert] } }
      expect(inserts).not_to include(a_string_starting_with("/login"))
    end
  end

  it "includes a Conversations section with /new and /resume" do
    conv = sections.find { |s| s[:title_key].include?("conversations") }
    expect(conv).to be_present
    inserts = conv[:items].map { |i| i[:insert] }
    expect(inserts).to include("/new", "/resume")
  end

  it "has no duplicate insert values" do
    inserts = sections.flat_map { |s| s[:items].map { |i| i[:insert] } }
    expect(inserts).to eq(inserts.uniq)
  end
end
