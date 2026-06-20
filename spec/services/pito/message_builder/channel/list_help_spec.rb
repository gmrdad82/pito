# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::ListHelp do
  describe ".call" do
    subject(:result) { described_class.call }

    it "returns an html payload" do
      expect(result).to be_a(Hash)
      expect(result["html"]).to be(true)
      expect(result["body"]).to be_a(String)
    end

    it "body is wrapped in .pito-help-block" do
      expect(result["body"]).to include('class="pito-help-block"')
    end

    it "body includes 'Usage:'" do
      expect(result["body"]).to include("Usage:")
    end

    it "body includes the list channels usage line" do
      expect(result["body"]).to include("list channels")
    end

    it "body includes Options section" do
      expect(result["body"]).to include("Options:")
    end

    it "body includes --help option" do
      expect(result["body"]).to include("--help")
    end

    it "body includes the --help description" do
      expect(result["body"]).to include("Print this help message")
    end

    it "body does not append content outside the pito-help-block div" do
      body = result["body"]
      # Everything after the closing </div> should be empty
      after_div = body.split("</div>", 2).last.to_s
      expect(after_div.strip).to be_empty
    end
  end
end
