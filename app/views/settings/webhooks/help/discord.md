# Discord webhook setup

This guide walks you through creating a Discord webhook so Pito can
deliver notifications to a Discord channel.

## Step 1 — Open the channel settings

In Discord, navigate to the server and channel where you want Pito
notifications to land.

Click the gear icon next to the channel name to open **Channel Settings**.

## Step 2 — Create a webhook

In the left sidebar, click **Integrations**.

Click **Webhooks** → **[New Webhook]**.

Give the webhook a name (e.g. "Pito") and optionally an avatar image.

Pick the channel destination (it should default to the channel you opened).

Click **[Copy Webhook URL]**. It looks like:

    https://discord.com/api/webhooks/1234567890/abcdef-ghijkl-mnopqr

Click **[Save Changes]**.

## Step 3 — Paste into Pito

Paste the URL into the Discord pane's **webhook URL** field on Pito's
Settings page. Click **[update]**.

Pito will send a test message to the channel. If you see "Pito test
ping — Discord webhook configured." in the channel, you're done.

If the test fails, double-check the URL has no extra whitespace and
that the webhook still exists. The URL is verified before it's saved.

## Notifications behavior

Toggle **deliver every notification** to receive every Pito notification.

Toggle **daily digest** to receive a single summary message per day at
09:00 in your configured time zone.

Both toggles work independently.
