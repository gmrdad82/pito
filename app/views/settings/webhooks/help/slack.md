# Slack webhook setup

This guide walks you through creating a Slack Incoming Webhook so Pito
can deliver notifications to a Slack channel.

## Step 1 — Create a Slack app

Open https://api.slack.com/apps in your browser. Sign in if needed.

Click **[Create New App]** in the top right. Pick **From scratch**.

Name the app `Pito notifications` (or whatever you prefer). Pick the
Slack workspace where notifications should land. Hit **[Create App]**.

## Step 2 — Enable Incoming Webhooks

In the app's left sidebar, click **Incoming Webhooks**.

Toggle **Activate Incoming Webhooks** to **On**.

## Step 3 — Add a webhook URL to a channel

Scroll to the bottom of the page. Click **[Add New Webhook to Workspace]**.

Pick the channel where Pito notifications should appear. Click **[Allow]**.

You'll see the new webhook URL listed near the bottom. It looks like:

    https://hooks.slack.com/services/T01234ABCDE/B01234ABCDE/abcdef123456

Copy that URL.

## Step 4 — Paste into Pito

Paste the URL into the Slack pane's **webhook URL** field on Pito's
Settings page. Click **[update]**.

Pito will send a test message to the channel. If you see "Pito test
ping — Slack webhook configured." in the channel, you're done.

If the test fails, double-check the URL has no extra whitespace and
that the channel still exists. The URL is verified before it's saved
so a bad URL never persists.

## Notifications behavior

Toggle **deliver every notification** to receive every Pito notification
(channel sync diffs, video import results, etc.).

Toggle **daily digest** to receive a single summary message per day
at 09:00 in your configured time zone.

Both toggles work independently. Turn one on, both, or neither.
