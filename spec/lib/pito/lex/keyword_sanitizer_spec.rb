# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Lex::KeywordSanitizer do
  def sanitize(input)
    described_class.call(Pito::Lex::Lexer.call(input)).reject { |t| t.type == :eof }
  end

  def values(input)
    sanitize(input).map(&:value)
  end

  describe "downcasing titleized command keywords (phone auto-titleization)" do
    it "downcases a titleized verb (`List` → `list`)" do
      expect(values("List games")).to eq(%w[list games])
    end

    it "downcases a titleized verb before a numeric ref (`Show 5`)" do
      expect(values("Show 5")).to eq(%w[show 5])
    end

    it "downcases connectors and time words (`Schedule 22 Tomorrow At 14:30`)" do
      expect(values("Schedule 22 Tomorrow At")).to eq(%w[schedule 22 tomorrow at])
    end

    it "downcases the `To` connector (`link To vid 5`)" do
      expect(values("link To vid 5")).to eq(%w[link to vid 5])
    end

    it "downcases sort connectors and directions (`sort By views Desc`)" do
      expect(values("sort By views Desc")).to eq(%w[sort by views desc])
    end

    it "downcases weekday + noon (`Saturday At Noon`)" do
      expect(values("schedule 5 Saturday At Noon")).to eq(%w[schedule 5 saturday at noon])
    end
  end

  describe "preserving non-keyword content" do
    it "keeps free-text title words (not keywords) in their original case" do
      expect(values("import game Demons Souls Remake")).to eq(%w[import game Demons Souls Remake])
    end

    it "never touches quoted (:string) literals" do
      tokens = sanitize('find "Lies of P"')
      string = tokens.find { |t| t.type == :string }
      expect(string.value).to eq("Lies of P")
    end

    it "leaves numbers untouched" do
      expect(values("price set 12 59.99")).to eq(%w[price set 12 59 . 99])
    end

    it "is idempotent (already-lowercase keywords unchanged)" do
      expect(values("list games with footage")).to eq(%w[list games with footage])
    end
  end
end
