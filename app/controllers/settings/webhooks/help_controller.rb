# Phase 26 — 01d. Help-modal Markdown guides for the Slack + Discord
# webhook panes.
#
# Single `show` action behind `/settings/webhooks/help/:provider`. The
# `[help]` link in each pane (Slack + Discord) targets this endpoint
# via a Turbo Frame; the response is rendered into the layout-level
# help modal hosted by the `webhook-help-modal` Stimulus controller.
#
# The :provider param is constrained at the router (`/slack|discord/`)
# so a malformed param 404s before reaching the action. As a
# defense-in-depth measure the action also checks the allow-list and
# 404s if anything else slips through.
#
# Markdown is rendered through `ApplicationHelper#render_markdown`
# (Commonmarker, hardbreaks: true) — the same renderer the note
# editor's SSR preview uses, so the help guides pick up the same
# syntax handling and HTML escape posture. Raw HTML in the .md files
# is escaped (no `unsafe_` extensions enabled).
#
# No layout — the response is a Turbo Frame fragment meant to be
# swapped into the modal. The frame id `webhook_help_modal_frame`
# matches the layout's `<turbo-frame>` element.
class Settings::Webhooks::HelpController < ApplicationController
  ALLOWED_PROVIDERS = %w[slack discord].freeze

  def show
    provider = params[:provider].to_s
    unless ALLOWED_PROVIDERS.include?(provider)
      render plain: "Not found", status: :not_found
      return
    end

    @provider = provider
    @markdown = read_guide(provider)
    render layout: false
  end

  private

  # Reads the on-disk Markdown guide for the named provider. Lives
  # under `app/views/settings/webhooks/help/` so the files travel with
  # the view tree (and ship in the assets payload at deploy time).
  def read_guide(provider)
    path = Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md")
    path.exist? ? path.read : ""
  end
end
