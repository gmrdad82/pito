# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Pito::Tools::Clean do
  it "wipes tmp/ except storage, pids, and .keep; truncates dev logs" do
    Dir.mktmpdir do |root|
      r = Pathname(root)
      %w[tmp/cache tmp/sockets tmp/storage tmp/pids tmp/Logos log].each { |d| FileUtils.mkdir_p(r.join(d)) }
      File.write(r.join("tmp/.keep"), "")
      File.write(r.join("tmp/cache/x"), "junk")
      File.write(r.join("tmp/Logos/a.png"), "owner-dumped")  # disposable per owner decision
      File.write(r.join("tmp/loose.txt"), "junk")
      File.write(r.join("tmp/storage/blob.dat"), "test blob") # protected
      File.write(r.join("tmp/pids/server.pid"), "1234")       # protected
      File.write(r.join("log/development.log"), "x" * 100)

      cleared = described_class.call(root: r)

      # Wiped (tmp/ is disposable):
      expect(r.join("tmp/cache")).not_to exist
      expect(r.join("tmp/sockets")).not_to exist
      expect(r.join("tmp/Logos")).not_to exist
      expect(r.join("tmp/loose.txt")).not_to exist
      expect(File.size(r.join("log/development.log"))).to eq(0)
      # Protected:
      expect(r.join("tmp/storage/blob.dat")).to exist
      expect(r.join("tmp/pids/server.pid")).to exist
      expect(r.join("tmp/.keep")).to exist

      expect(cleared).to include("log/*.log")
      expect(cleared.any? { |c| c.start_with?("tmp/*") }).to be(true)
    end
  end

  it "is a safe no-op when tmp + logs are absent" do
    Dir.mktmpdir { |root| expect(described_class.call(root: Pathname(root))).to eq([]) }
  end
end
