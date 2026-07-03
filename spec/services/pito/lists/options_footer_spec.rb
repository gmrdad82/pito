# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Lists::OptionsFooter do
  describe ".call" do
    # All three inputs empty → nothing to tell the user.
    it "returns nil when all inputs are empty" do
      expect(described_class.call(addable: [], removable: [], sort_keys: [])).to be_nil
    end

    # Full args: both a columns line and a sort line are joined by a space.
    # Assert on the interpolated values (%{addable} and %{keys} always appear
    # in the selected copy variants) rather than on exact dictionary text.
    it "joins the columns and sort lines with a space when both are present" do
      result = described_class.call(
        addable:   %w[views comments],
        removable: %w[channel],
        sort_keys: %w[id title channel]
      )
      expect(result).to be_a(String)
      # The addable list is always interpolated into the columns line.
      expect(result).to include("views, comments")
      # The sort keys are always interpolated into the sort line.
      expect(result).to include("id, title, channel")
    end

    # Sort keys empty → only the columns line is rendered.
    it "renders only the columns line when sort_keys is empty" do
      result = described_class.call(
        addable:   %w[views],
        removable: %w[channel],
        sort_keys: []
      )
      expect(result).to be_a(String)
      expect(result).to include("views")
      # No sort line → the word "sort" does not appear (all sort variants contain it).
      expect(result).not_to include("sort")
    end

    # Addable and removable both empty but sort_keys present → only the sort line.
    it "renders only the sort line when addable and removable are both empty" do
      result = described_class.call(
        addable:   [],
        removable: [],
        sort_keys: %w[handle title subs views vids]
      )
      expect(result).to be_a(String)
      expect(result).to include("handle, title, subs, views, vids")
    end

    # Empty addable side is substituted with the literal "nothing".
    it "renders 'nothing' for the addable placeholder when addable is empty" do
      result = described_class.call(
        addable:   [],
        removable: %w[channel visibility],
        sort_keys: []
      )
      expect(result).to include("nothing")
    end

    # When addable is non-empty but removable is empty the columns line is still
    # rendered (nil contract only triggers when BOTH sides are empty). The addable
    # content always appears in the output — %{addable} is present in all copy variants.
    it "still renders the columns line when removable is empty but addable is not" do
      result = described_class.call(
        addable:   %w[views],
        removable: [],
        sort_keys: []
      )
      expect(result).to be_a(String)
      expect(result).to include("views")
    end
  end
end
