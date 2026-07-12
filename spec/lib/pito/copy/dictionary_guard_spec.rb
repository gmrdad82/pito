# frozen_string_literal: true

require "rails_helper"

# Guard: every registered copy key under `pito.copy.*` must be 1-or-50 — it holds
# EITHER exactly 1 entry (a single/fixed line) OR a full dictionary of at least 50
# variants. Nothing in between (a half-filled 2..49 pool reads as repetitive). This
# runs against the REAL locale files, so any new command's copy that lands short of
# 50 fails here until it is filled.
RSpec.describe "Pito::Copy 1-or-50 dictionary guard", type: :service do
  MIN_DICTIONARY = 50

  # Audit the REAL locale files, immune to any prior spec that stored fixture
  # copy into the shared I18n backend without cleaning up.
  before { I18n.reload! }

  it "has no copy key with between 2 and #{MIN_DICTIONARY - 1} variants" do
    offenders = Pito::Copy::Audit.call.registered
      .select { |leaf| leaf[:variants] > 1 && leaf[:variants] < MIN_DICTIONARY }

    report = offenders.map { |o| "  #{o[:variants].to_s.rjust(3)}  #{o[:key]}" }.join("\n")

    expect(offenders).to(
      be_empty,
      "These copy keys must be a single line (1) or a full dictionary (>= #{MIN_DICTIONARY}); " \
      "fill or trim them:\n#{report}"
    )
  end

  it "every registered key is therefore 1 or >= #{MIN_DICTIONARY}" do
    Pito::Copy::Audit.call.registered.each do |leaf|
      expect(leaf[:variants] == 1 || leaf[:variants] >= MIN_DICTIONARY)
        .to be(true), "#{leaf[:key]} has #{leaf[:variants]} variants"
    end
  end
end
