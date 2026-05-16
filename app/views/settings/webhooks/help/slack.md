# Slack webhook setup

## Step 1 — Create a Slack app

Open the [Slack apps directory](https://api.slack.com/apps), sign in to the
workspace where pings should land, click `Create New App` → `From scratch`.

Name it `pito` (or any label), pick the workspace, `Create App`.

---

## Step 2 — Enable Incoming Webhooks

Sidebar → `Incoming Webhooks`. Flip `Activate Incoming Webhooks` to `On`.

---

## Step 3 — Add a webhook URL

Same page, bottom: `Add New Webhook to Workspace`. Pick a channel (public,
private you belong to, or self-DM), `Allow`.

A new row appears under "Webhook URLs for Your Workspace". Click `Copy`.

URL shape:

    https://hooks.slack.com/services/T012/B012/abcdef

---

## Step 4 — Paste into pito

Settings → Slack pane. Paste into `webhook URL`, click `[update]`.

Pito validates the URL shape (`https://hooks.slack.com/services/` + three
slash-separated segments) and sends a test ping. The URL is saved only if Slack
accepts it.

You should see in the channel within ~1s:

    pito test ping — Slack webhook configured.

---

## Troubleshooting

| Error                    | Fix                                      |
| ------------------------ | ---------------------------------------- |
| **URL invalid**          | re-copy from Slack                       |
| **test ping 404 / 410**  | webhook deleted — redo Step 3            |
| **test ping 403**        | workspace perms changed — redo Step 3    |
| **connection timed out** | network / `hooks.slack.com` reachability |
| **channel disappeared**  | channel deleted — redo Step 3 elsewhere  |

To reset: clear the `webhook URL` field and `[update]`. Toggles reset to off.
