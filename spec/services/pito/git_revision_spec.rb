# frozen_string_literal: true

require "rails_helper"

# Pito::GitRevision captures SHA and BRANCH at boot time via shell-outs.
# In the test environment the Rails.root IS a real git checkout, so the
# constants are non-nil.  Tests verify the interface contract without
# asserting exact commit values (those change every commit).
RSpec.describe Pito::GitRevision do
  describe "constants" do
    it "defines REPO_SLUG as the canonical gmrdad82/pito string" do
      expect(described_class::REPO_SLUG).to eq("gmrdad82/pito")
    end

    it "captures SHA as a String or nil (nil only outside a git checkout)" do
      expect(described_class::SHA).to satisfy("be a String or nil") { |v|
        v.nil? || v.is_a?(String)
      }
    end

    it "captures BRANCH as a String or nil" do
      expect(described_class::BRANCH).to satisfy("be a String or nil") { |v|
        v.nil? || v.is_a?(String)
      }
    end
  end

  describe ".sha" do
    it "returns the SHA constant" do
      expect(described_class.sha).to eq(described_class::SHA)
    end

    it "returns a 40-character hex string when inside a git checkout" do
      sha = described_class.sha
      if sha
        expect(sha).to match(/\A[0-9a-f]{40}\z/)
      else
        skip "Not inside a git checkout — SHA is nil"
      end
    end
  end

  describe ".branch" do
    it "returns the BRANCH constant" do
      expect(described_class.branch).to eq(described_class::BRANCH)
    end

    it "returns a non-empty String when inside a git checkout" do
      branch = described_class.branch
      if branch
        expect(branch).to be_a(String)
        expect(branch).not_to be_empty
      else
        skip "Not inside a git checkout — BRANCH is nil"
      end
    end
  end

  describe ".short_sha" do
    it "returns nil when SHA is nil" do
      stub_const("#{described_class}::SHA", nil)
      expect(described_class.short_sha).to be_nil
    end

    it "returns first 7 characters of SHA when SHA is present" do
      stub_const("#{described_class}::SHA", "abcdef1234567890")
      expect(described_class.short_sha).to eq("abcdef1")
    end
  end

  describe ".commit_url" do
    it "returns nil when SHA is nil" do
      stub_const("#{described_class}::SHA", nil)
      expect(described_class.commit_url).to be_nil
    end

    it "returns a GitHub commit URL when SHA is present" do
      stub_const("#{described_class}::SHA", "abc123")
      url = described_class.commit_url
      expect(url).to eq("https://github.com/gmrdad82/pito/commit/abc123")
    end

    it "includes the REPO_SLUG in the URL" do
      stub_const("#{described_class}::SHA", "deadbeef")
      expect(described_class.commit_url).to include(described_class::REPO_SLUG)
    end
  end
end
