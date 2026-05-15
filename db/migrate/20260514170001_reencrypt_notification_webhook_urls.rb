# Phase 29 — Unit A1. Defensive re-encryption pass for
# `notification_delivery_channels.webhook_url`.
#
# `encrypts :webhook_url` (Active Record Encryption, probabilistic) has
# been on the model since the column's creation migration (Phase 26),
# so there is no plaintext data to re-encrypt and no production data at
# all — this migration is belt-and-suspenders. Re-saving every row
# through the encrypting writer documents the "webhook URLs are
# encrypted at rest" invariant and forwards-fixes any row that might
# ever have been written before `encrypts` landed.
#
# `data` migration — no schema change. Safe on an empty table (the
# realistic case). `save(validate: false)` so a row whose URL no longer
# matches the current per-kind regex still gets re-encrypted rather than
# blocking the migration.
class ReencryptNotificationWebhookUrls < ActiveRecord::Migration[8.1]
  def up
    NotificationDeliveryChannel.reset_column_information
    NotificationDeliveryChannel.find_each do |channel|
      channel.save!(validate: false)
    end
  end

  def down
    # No-op — re-encryption is not reversible and carries no schema
    # change. Rolling back leaves the rows encrypted (the desired
    # at-rest state regardless).
  end
end
