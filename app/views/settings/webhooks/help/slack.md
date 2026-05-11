# Slack webhook setup

This guide walks you, step by step, from never having made a Slack
webhook to receiving a pito test ping in your Slack channel. No prior
Slack-admin experience needed — if you can sign in to Slack, you can
follow this.

A Slack webhook is just a URL: when something sends an HTTP POST to
that URL, Slack writes the request body as a message in the channel
you picked. Pito uses this to deliver notifications.

## Step 1 — Create a Slack app

Open https://api.slack.com/apps in your browser. Sign in if needed —
use the same account that has access to the Slack workspace you want
notifications to land in.

Click `Create New App` in the top right. A dialog asks how you'd like
to configure your new app — pick `From scratch`.

In the next dialog:

- App Name — type `pito` (or any name you'll recognize later).
- Pick a workspace — pick the Slack workspace where notifications
  should land.

Hit `Create App`. Slack drops you on the app's "Basic Information"
page.

## Step 2 — Enable Incoming Webhooks

In the left sidebar (under "Features"), click `Incoming Webhooks`.

At the top of that page is a toggle labelled "Activate Incoming
Webhooks". Flip it from `Off` to `On`. The page expands to show
webhook configuration.

## Step 3 — Add a webhook URL to a channel

Scroll to the bottom of the same page. Click
`Add New Webhook to Workspace`.

Slack asks which channel pito should be allowed to post to. Pick the
channel (it can be a public channel, a private channel you belong to,
or a DM to yourself). Click `Allow`.

You bounce back to the "Incoming Webhooks" page. Near the bottom, in
the "Webhook URLs for Your Workspace" table, there's now a new row
with a URL that looks like:

    https://hooks.slack.com/services/T01234ABCDE/B01234ABCDE/abcdef123456

Click the `Copy` button next to that URL.

## Step 4 — Paste into Pito

Switch back to pito. On the Settings page, find the Slack pane. Paste
the URL into the `webhook URL` field.

Click `[update]`.

Pito does two things:

1. Validates the URL shape — it must start with
   `https://hooks.slack.com/services/` and have the three path
   segments above.
2. Sends a test message to the channel. Only if Slack accepts the
   message does pito save the URL.

Within a second, the Slack channel should show a message that reads:

    pito test ping — Slack webhook configured.

That's it. You're done.

## Notifications behavior

Two checkboxes live below the URL field:

- `deliver every notification` — pito posts to Slack every time it
  generates a notification (channel sync diffs, video import results,
  scheduled-publish reminders, etc.).
- `daily digest` — pito posts a single roll-up message at 09:00 in
  your configured time zone, summarising the previous 24 hours.

The two toggles work independently. Turn one on, both on, or
neither. Both off means the URL is saved but pito stays quiet — handy
if you want to wire the integration up first and switch it on later.

## Troubleshooting

**"webhook URL is invalid"** — the URL shape doesn't match. Slack
webhook URLs always start with `https://hooks.slack.com/services/`
and have three slash-separated segments after `services/`. Re-copy
the URL from Slack and try again. Stray whitespace before or after
the URL is stripped automatically.

**"test ping failed: Slack returned 404 / 410"** — the webhook was
deleted in Slack (someone clicked `Remove` in the Webhook URLs table,
or removed the entire app). Re-run Step 3 to create a fresh URL and
paste the new one.

**"test ping failed: Slack returned 403"** — the workspace
permissions changed and the app no longer has access to the chosen
channel. Re-run Step 3 and pick a channel you currently have access
to.

**"test ping failed: connection timed out"** — pito couldn't reach
`hooks.slack.com`. Usually a network blip; try again in a moment. If
it persists, check that outbound HTTPS to `hooks.slack.com` is
allowed from the host running pito.

**The channel disappeared** — if the Slack channel was deleted after
you saved the URL, the next pito delivery attempt will fail. Re-run
Step 3 against a different channel and paste the new URL into the
Slack pane.

**Need to start over** — clear the `webhook URL` field and click
`[update]`. Pito removes the saved configuration. Both toggles reset
to off automatically.
