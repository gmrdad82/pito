# Discord webhook setup

This guide walks you, step by step, from never having made a Discord
webhook to receiving a pito test ping in your Discord channel.

No prior Discord-admin experience needed — if you can open Discord
and see a channel's gear icon, you can follow this.

A Discord webhook is just a URL.

When something sends an HTTP POST to that URL, Discord writes the
request body as a message in the channel you picked. Pito uses this
to deliver notifications.

**Before you start:** you need the `Manage Webhooks` permission on
the channel you'll target. On a Discord server you own, this is
automatic. On a server you're a member of, ask the owner or an admin
to grant the role — without it the menu in Step 2 won't appear.

---

## Step 1 — Open the channel settings

Open Discord (desktop, browser, or mobile — all three work).

Navigate to the server, then to the specific channel where pito
notifications should land.

Hover over the channel name in the channel list. A small gear icon
appears next to it. Click the gear to open `Channel Settings`.

Alternative path: right-click the channel → `Edit Channel`. Same
destination.

---

## Step 2 — Create a webhook

In the left sidebar of the Channel Settings panel, click
`Integrations`.

The Integrations page lists what's already wired up (often empty on
a fresh server). Find the `Webhooks` section and click it.

Click `New Webhook` (or `Create Webhook` if this is the first one).
Discord drops a freshly-created webhook into the list, named
something like "Captain Hook" with the default Discord avatar.

Expand the new entry. The form has:

| Field   | What to do                                              |
| ------- | ------------------------------------------------------- |
| Name    | change it to `pito` (or any name you'll recognise)      |
| Channel | leave the default, or pick another channel in the server |
| Avatar  | optional — click to upload a custom image               |

Click `Copy Webhook URL` at the bottom of the form. The URL looks
like:

    https://discord.com/api/webhooks/123456789/aBcDeF-GhIjKl

Click `Save Changes` to persist the webhook in Discord.

Tip: copy the URL **after** saving so the webhook actually exists
when pito tests it.

---

## Step 3 — Paste into pito

Switch back to pito. On the Settings page, find the Discord pane.

Paste the URL into the `webhook URL` field, then click `[update]`.

Pito does two things:

1. **Validates the URL shape.** It must start with
   `https://discord.com/api/webhooks/` or
   `https://discordapp.com/api/webhooks/` (both Discord host names
   are accepted) and carry the numeric-id + token segments.
2. **Sends a test message** to the channel. Only if Discord accepts
   the message does pito save the URL.

Within a second, the Discord channel should show:

    pito test ping — Discord webhook configured.

That's it. You're done.

---

## Notifications behavior

Two checkboxes live below the URL field:

| Checkbox                       | What it does                                              |
| ------------------------------ | --------------------------------------------------------- |
| `deliver every notification`   | post to Discord every time pito generates a notification  |
| `daily digest`                 | post a single roll-up at 09:00 in your time zone          |

The two toggles work independently. Turn one on, both on, or neither.

Both off means the URL is saved but pito stays quiet — handy if you
want to wire the integration up first and switch it on later.

---

## Troubleshooting

| Error message                              | What it means                                  | What to do                                                |
| ------------------------------------------ | ---------------------------------------------- | --------------------------------------------------------- |
| **webhook URL is invalid**                 | URL shape doesn't match Discord's pattern      | re-copy the URL from Discord; stray whitespace is fine    |
| **test ping failed: Discord returned 404** | the webhook was deleted in Discord             | re-run Step 2 and paste the new URL                       |
| **test ping failed: Discord returned 401** | the token portion of the URL is wrong or reset | re-run Step 2 and copy the URL fresh                      |
| **test ping failed: connection timed out** | pito couldn't reach `discord.com`              | usually a network blip; retry; check outbound HTTPS       |
| **can't see the Integrations menu**        | you lack `Manage Webhooks` on the channel      | ask the server owner or an admin to grant the role        |
| **the channel disappeared**                | the Discord channel was deleted after save     | re-run Step 2 against a different channel; paste new URL  |

### Need to start over

Clear the `webhook URL` field and click `[update]`. Pito removes the
saved configuration. Both toggles reset to off automatically.
