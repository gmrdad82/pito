require "rails_helper"
require Rails.root.join(
  "db/migrate/20260514170001_reencrypt_notification_webhook_urls.rb"
)

# Phase 29 — Unit A1. The defensive re-encryption migration. It is
# expected to be a no-op in practice (`encrypts :webhook_url` has been
# on the model since the column's creation), but the regression
# mandate wants it specced: it must run cleanly on an empty table and
# on a table with rows, leaving the decrypted `webhook_url` intact.
RSpec.describe ReencryptNotificationWebhookUrls, type: :model do
  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

  it "runs cleanly on an empty table" do
    NotificationDeliveryChannel.delete_all
    expect { described_class.new.migrate(:up) }.not_to raise_error
  end

  it "leaves the decrypted webhook_url intact for an existing row" do
    NotificationDeliveryChannel.delete_all
    NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)

    described_class.new.migrate(:up)

    expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(slack_url)
  end

  it "re-saves every row (multiple kinds) without altering the plaintext" do
    NotificationDeliveryChannel.delete_all
    NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
    NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)

    described_class.new.migrate(:up)

    expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(slack_url)
    expect(NotificationDeliveryChannel.find_by(kind: "discord").webhook_url).to eq(discord_url)
  end

  it "leaves the stored value as ciphertext (still encrypted at rest)" do
    NotificationDeliveryChannel.delete_all
    NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)

    described_class.new.migrate(:up)

    raw = NotificationDeliveryChannel.connection.select_value(
      "SELECT webhook_url FROM notification_delivery_channels WHERE kind = 'slack'"
    )
    expect(raw).not_to include("hooks.slack.com")
  end

  it "`down` is a clean no-op" do
    expect { described_class.new.migrate(:down) }.not_to raise_error
  end
end
