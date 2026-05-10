# Phase 16 — Notifications — Closed (2026-05-10)

## Goal

In-app notifications with Discord/Slack outbound delivery, MCP tools, formatter
pipeline (markdown → in-app HTML / Discord embed / Slack mrkdwn / MCP markdown),
notification UI with badge + filter + bulk + modal-detail + 7-day cleanup cron.

## Status

DONE. All 3 specs in main + reviewers + Specs 01/02/03 security audits + F1-F4
fix-forward (Spec 01) + F1+F2+F3 fix-forward (Spec 02/03).

## Links

- Specs: `docs/plans/beta/16-notifications/specs/{01,02,03}-*.md`
- Reviewer playbooks: `docs/orchestration/playbooks/2026-05-10-phase-16-*.md`
- Security playbooks:
  `docs/orchestration/playbooks/security-2026-05-10-phase-16-*.md`
- Phase log: `docs/plans/beta/16-notifications/log.md`

## Key changes

- 4 channels (in-app, Discord webhook, Slack webhook, MCP)
- 4 formatters with shared markdown link rewriting
- URL scheme allowlist (http/https/mailto + leading-slash app paths) on every
  formatter — `javascript:`, `data:`, `vbscript:`, protocol-relative all
  stripped
- Webhook outbound HTTP timeouts + TLS + body-size cap (Spec 01 F1-F4)
- Per-user mark-read rate limit (5s Redis cache lock; 302 HTML / 429 JSON
  envelope)
- Superscript badge (no brackets); empty state; [ ] unread filter chip
- Bulk action checkboxes; dynamic [mark all as read] button text
- Modal-based detail view via Turbo Frame
- NotificationCleanupJob (7-day delete after read; cron 03:30 daily)

## Validation

Walk reviewer playbook (24 steps): badge in dark mode, click row → modal,
partial selection → dynamic button text, chip toggle, sidekiq web shows
`notification_cleanup` scheduled, etc.

## Open follow-ups

- Settings UI for `discord_enabled` / `slack_enabled` flags
- Spec 02/03 F4-F7 (low; defense-in-depth) — queued
