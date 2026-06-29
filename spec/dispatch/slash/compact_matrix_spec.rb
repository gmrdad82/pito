# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dispatch matrix — compact (recognition, DB mocked)", type: :dispatch do
  describe "recognition" do
    [ "/compact", "/compact --help" ].each do |input|
      it "#{input.inspect} → stack :slash, verb :compact, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:compact)
      end
    end

    it "requires authentication" do
      expect(parsed_intent("/compact")[:auth]).to eq(:authenticated_only)
    end
  end
end
