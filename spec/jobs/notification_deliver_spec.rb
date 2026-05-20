require "rails_helper"

RSpec.describe NotificationDeliver do
  let(:notification) { create(:notification) }

  describe "#perform" do
    it "in_app channel: synchronous, no HTTP, returns ok-shaped result" do
      expect_any_instance_of(::Net::HTTP).not_to receive(:request)
      expect { described_class.new.perform(notification.id, "in_app") }
        .not_to raise_error
    end

    # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The Slack / Discord delivery
    # gate is the AND of:
    #   - Shared toggle ON on `AppSetting.singleton_row`.
    #   - A `NotificationDeliveryChannel` row with a present
    #     `webhook_url`.
    # The per-brand routing-flag columns were dropped.
    it "discord channel: routes to the Discord channel and stamps the column on success" do
      AppSetting.delete_all
      NotificationDeliveryChannel.delete_all
      url = "https://discord.com/api/webhooks/abc"
      row = NotificationDeliveryChannel.new(kind: "discord", webhook_url: url)
      row.save!(validate: false)
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      stub_request(:post, url).to_return(status: 204, body: "")

      expect { described_class.new.perform(notification.id, "discord") }
        .to change { notification.reload.discord_delivered_at }.from(nil)
    end

    it "slack channel: routes to the Slack channel and stamps the column on success" do
      AppSetting.delete_all
      NotificationDeliveryChannel.delete_all
      url = "https://hooks.slack.com/services/abc"
      row = NotificationDeliveryChannel.new(kind: "slack", webhook_url: url)
      row.save!(validate: false)
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      stub_request(:post, url).to_return(status: 200, body: "ok")

      expect { described_class.new.perform(notification.id, "slack") }
        .to change { notification.reload.slack_delivered_at }.from(nil)
    end

    it "raises ArgumentError for an unknown channel kind" do
      expect { described_class.new.perform(notification.id, "email") }
        .to raise_error(ArgumentError, /unknown channel/)
    end

    it "silently no-ops when the notification was deleted between enqueue and run" do
      missing_id = Notification.maximum(:id).to_i + 1_000_000
      expect { described_class.new.perform(missing_id, "in_app") }
        .not_to raise_error
    end
  end

  describe "Sidekiq retry config" do
    it "is configured for 5 retries" do
      opts = described_class.sidekiq_options
      expect(opts["retry"]).to eq(5)
    end
  end

  describe "sidekiq_retry_in ladder" do
    let(:proc_block) { described_class.sidekiq_retry_in_block }

    it "implements the 1m / 5m / 15m / 1h / 6h ladder" do
      expect(proc_block.call(0, nil, nil)).to eq(60)
      expect(proc_block.call(1, nil, nil)).to eq(300)
      expect(proc_block.call(2, nil, nil)).to eq(900)
      expect(proc_block.call(3, nil, nil)).to eq(3600)
      expect(proc_block.call(4, nil, nil)).to eq(21_600)
    end

    it "tail-pads at 6h for any retry index past 4" do
      expect(proc_block.call(5, nil, nil)).to eq(21_600)
      expect(proc_block.call(99, nil, nil)).to eq(21_600)
    end
  end
end
