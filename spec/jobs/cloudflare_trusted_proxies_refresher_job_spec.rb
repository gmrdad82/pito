require "rails_helper"

# 2026-05-11 F5 — Cloudflare trusted-proxies drift watchdog.
RSpec.describe CloudflareTrustedProxiesRefresherJob, type: :job do
  # The job parses the literal `config/environments/production.rb`
  # file at runtime, so the specs that compare "fetched vs pinned"
  # do not need to stub the file read — the pinned list is whatever
  # production.rb declares today. We stub only the two HTTP fetches.
  let(:pinned) do
    described_class.new.send(:pinned_cidrs)
  end

  describe "#perform — no drift" do
    it "creates no Notification when fetched ranges match the pinned list" do
      stub_request(:get, described_class::IPS_V4_URL)
        .to_return(status: 200, body: pinned.select { |c| c.include?(".") }.join("\n") + "\n")
      stub_request(:get, described_class::IPS_V6_URL)
        .to_return(status: 200, body: pinned.reject { |c| c.include?(".") }.join("\n") + "\n")

      expect { described_class.new.perform }
        .not_to change(Notification, :count)
    end
  end

  describe "#perform — drift detected" do
    it "creates a sync_error Notification when Cloudflare adds a new range" do
      added_range = "203.0.113.0/24" # TEST-NET-3 (documentation block)
      stub_request(:get, described_class::IPS_V4_URL)
        .to_return(
          status: 200,
          body: (pinned.select { |c| c.include?(".") } + [ added_range ]).join("\n")
        )
      stub_request(:get, described_class::IPS_V6_URL)
        .to_return(
          status: 200,
          body: pinned.reject { |c| c.include?(".") }.join("\n")
        )

      expect { described_class.new.perform }
        .to change(Notification, :count).by(1)

      notif = Notification.last
      expect(notif.kind).to eq("sync_error")
      expect(notif.event_type).to eq("cloudflare_trusted_proxies_drift")
      expect(notif.body).to include(added_range)
      expect(notif.body).to include("Newly published")
    end

    it "creates a Notification when a pinned range is no longer published" do
      # Drop the FIRST pinned v4 range from the fetched body.
      v4_pinned = pinned.select { |c| c.include?(".") }
      v6_pinned = pinned.reject { |c| c.include?(".") }
      removed_range = v4_pinned.first

      stub_request(:get, described_class::IPS_V4_URL)
        .to_return(status: 200, body: v4_pinned.drop(1).join("\n"))
      stub_request(:get, described_class::IPS_V6_URL)
        .to_return(status: 200, body: v6_pinned.join("\n"))

      expect { described_class.new.perform }
        .to change(Notification, :count).by(1)

      notif = Notification.last
      expect(notif.body).to include(removed_range)
      expect(notif.body).to include("No longer published")
    end

    it "collapses two same-day drift runs to a single Notification row" do
      stub_request(:get, described_class::IPS_V4_URL)
        .to_return(status: 200, body: "")
      stub_request(:get, described_class::IPS_V6_URL)
        .to_return(status: 200, body: "")

      # Both fetches return empty bodies — i.e., Cloudflare "no
      # longer publishes" every pinned range. First run drafts a
      # drift notification; second run hits the dedup_key partial
      # index and collapses cleanly.
      described_class.new.perform
      expect { described_class.new.perform }.not_to change(Notification, :count)
    end
  end

  describe "#perform — fetch failures (defensive)" do
    it "logs and does NOT raise when ips-v4 fetch fails" do
      stub_request(:get, described_class::IPS_V4_URL).to_raise(SocketError.new("dns"))
      stub_request(:get, described_class::IPS_V6_URL)
        .to_return(
          status: 200,
          body: pinned.reject { |c| c.include?(".") }.join("\n")
        )

      expect { described_class.new.perform }.not_to raise_error
    end

    it "logs and does NOT raise when ips-v6 fetch fails" do
      stub_request(:get, described_class::IPS_V4_URL)
        .to_return(
          status: 200,
          body: pinned.select { |c| c.include?(".") }.join("\n")
        )
      stub_request(:get, described_class::IPS_V6_URL).to_raise(Net::OpenTimeout.new("timeout"))

      expect { described_class.new.perform }.not_to raise_error
    end

    it "writes NO notification when BOTH fetches fail (cannot tell drift from outage)" do
      stub_request(:get, described_class::IPS_V4_URL).to_raise(SocketError.new("dns"))
      stub_request(:get, described_class::IPS_V6_URL).to_raise(SocketError.new("dns"))

      expect { described_class.new.perform }.not_to change(Notification, :count)
    end

    it "writes NO notification on a non-2xx response" do
      stub_request(:get, described_class::IPS_V4_URL).to_return(status: 503, body: "")
      stub_request(:get, described_class::IPS_V6_URL).to_return(status: 503, body: "")

      expect { described_class.new.perform }.not_to change(Notification, :count)
    end
  end

  describe "pinned_cidrs (private helper)" do
    it "extracts CIDR-shaped tokens from production.rb" do
      cidrs = described_class.new.send(:pinned_cidrs)
      expect(cidrs).not_to be_empty
      # Sanity: at least one IPv4 and one IPv6 range survives the regex.
      expect(cidrs.any? { |c| c.include?(".") }).to be(true)
      expect(cidrs.any? { |c| c.include?(":") }).to be(true)
    end
  end
end
