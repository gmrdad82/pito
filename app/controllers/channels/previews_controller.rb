module Channels
  # Phase 7.5 §11d — Channel multi-layout preview endpoint.
  #
  # GET `/channels/:channel_id/preview` returns a Turbo Stream that
  # replaces the `#channel-preview` frame inside the wide modal with
  # a freshly-rendered `ChannelPreviewComponent` reflecting the
  # `pending` edits the form streams through the query string.
  #
  # No DB writes. No HTML branch — the modal carries the initial
  # render server-side; the `show` action exists solely to refresh
  # the in-modal preview while the user is typing.
  class PreviewsController < ApplicationController
    PERMITTED_PARAMS = %i[title handle description banner_url avatar_url active_layout].freeze

    def show
      @channel = Channel.friendly.find(params[:channel_id])
      @pending = extract_pending(params)
      @active_layout = params[:active_layout].to_s.presence || ChannelPreviewComponent::DEFAULT_LAYOUT

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "channel-preview",
            ChannelPreviewComponent.new(
              channel: @channel,
              pending: @pending,
              active_layout: @active_layout
            )
          )
        end
        format.html do
          render(ChannelPreviewComponent.new(
            channel: @channel,
            pending: @pending,
            active_layout: @active_layout
          ), layout: false)
        end
      end
    end

    private

    # Collects only the keys the preview cares about (every other
    # query param is ignored) and stringifies values. The
    # `active_layout` key is consumed separately and stripped from
    # the pending hash so it never flows through as a fake
    # channel attribute.
    def extract_pending(params)
      pending = {}
      PERMITTED_PARAMS.each do |key|
        next if key == :active_layout
        next unless params.key?(key)

        pending[key.to_s] = params[key].to_s
      end

      # Links arrive as a `links_attributes` Hash from the
      # nested-attributes form (when the user has been editing
      # the links repeater). Flatten into the same `[{title:, url:}]`
      # shape the channel's jsonb column carries so the component's
      # `resolved_links` branch finds the right structure.
      if params[:links_attributes].present?
        pending["links"] = normalize_links(params[:links_attributes])
      elsif params[:links].is_a?(Array)
        pending["links"] = params[:links].map(&:to_unsafe_h)
      end

      pending
    end

    def normalize_links(raw)
      entries = case raw
      when ActionController::Parameters
                  raw.to_unsafe_h.values
      when Hash
                  raw.values
      when Array
                  raw
      else
                  []
      end

      entries.filter_map do |entry|
        hash = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        next unless hash.is_a?(Hash)
        next if hash["_destroy"].to_s == "yes" || hash["_destroy"].to_s == "1"

        title = (hash["title"] || hash[:title]).to_s.strip
        url   = (hash["url"] || hash[:url]).to_s.strip
        next if title.blank? || url.blank?

        { "title" => title, "url" => url }
      end
    end
  end
end
