# Slack webhook setup

This guide walks you, step by step, from never having made a Slack webhook to
receiving a pito test ping in your Slack channel.

No prior Slack-admin experience needed — if you can sign in to Slack, you can
follow this.

A Slack webhook is just a URL. See Slack's
[Incoming Webhooks](https://api.slack.com/messaging/webhooks) docs for the full
reference.

When something sends an HTTP POST to that URL, Slack writes the request body as
a message in the
[channel](https://slack.com/help/articles/360017938993-What-is-a-channel) you
picked. Pito uses this to deliver notifications.

---

## Step 1 — Create a Slack app

Open the [Slack apps directory](https://api.slack.com/apps) in your browser.
Sign in if needed — use the same account that has access to the Slack workspace
you want notifications to land in.

Click `Create New App` in the top right. A dialog asks how you'd like to
configure your new app — pick `From scratch`.

In the next dialog:

| Field          | What to do                                         |
| -------------- | -------------------------------------------------- |
| App Name       | type `pito` (or any name you'll recognize)         |
| Pick workspace | choose the Slack workspace where pings should land |

Hit `Create App`. Slack drops you on the app's "Basic Information" page.

---

## Step 2 — Enable Incoming Webhooks

In the left sidebar (under "Features"), click
[`Incoming Webhooks`](https://api.slack.com/messaging/webhooks#getting_started).

At the top of that page is a toggle labelled "Activate Incoming Webhooks". Flip
it from `Off` to `On`.

The page expands to show webhook configuration.

---

## Step 3 — Add a webhook URL to a channel

Scroll to the bottom of the same page. Click `Add New Webhook to Workspace`.

Slack asks which channel pito should be allowed to post to. Pick the channel —
it can be a public channel, a private channel you belong to, or a DM to
yourself. Click `Allow`.

You bounce back to the "Incoming Webhooks" page. Near the bottom, in the
"Webhook URLs for Your Workspace" table, there's a new row with a URL that looks
like:

    https://hooks.slack.com/services/T012/B012/abcdef

Click the `Copy` button next to that URL.

---

## Step 4 — Paste into pito

Switch back to pito. On the Settings page, find the Slack pane.

Paste the URL into the `webhook URL` field, then click `[update]`.

Pito does two things:

1. **Validates the URL shape.** It must start with
   `https://hooks.slack.com/services/` and have three slash- separated segments
   after `services/`.
2. **Sends a test message** to the channel. Only if Slack accepts the message
   does pito save the URL.

Within a second, the Slack channel should show:

    pito test ping — Slack webhook configured.

That's it. You're done.

---

## Notifications behavior

Two checkboxes live below the URL field:

| Checkbox                     | What it does                                           |
| ---------------------------- | ------------------------------------------------------ |
| `deliver every notification` | post to Slack every time pito generates a notification |
| `daily digest`               | post a single roll-up at 09:00 in your time zone       |

The two toggles work independently. Turn one on, both on, or neither.

Both off means the URL is saved but pito stays quiet — handy if you want to wire
the integration up first and switch it on later.

---

## Troubleshooting

| Error message                                  | What it means                                                                              | What to do                                               |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| **webhook URL is invalid**                     | URL shape doesn't match Slack's pattern                                                    | re-copy the URL from Slack; stray whitespace is fine     |
| **test ping failed: Slack returned 404 / 410** | the webhook was deleted in Slack ([Slack API errors](https://api.slack.com/web#responses)) | re-run Step 3 and paste the new URL                      |
| **test ping failed: Slack returned 403**       | workspace permissions changed; no channel access                                           | re-run Step 3 and pick a channel you can access          |
| **test ping failed: connection timed out**     | pito couldn't reach `hooks.slack.com`                                                      | usually a network blip; retry; check outbound HTTPS      |
| **the channel disappeared**                    | the Slack channel was deleted after save                                                   | re-run Step 3 against a different channel; paste new URL |

### Need to start over

Clear the `webhook URL` field and click `[update]`. Pito removes the saved
configuration. Both toggles reset to off automatically.
