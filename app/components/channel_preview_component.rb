# Phase 7.5 §11d — Channel multi-layout preview component.
#
# Renders a Pito-built mockup of the channel page at three viewport
# sizes — desktop (~1280px), mobile (~390px), and TV (1920×1080) —
# inside a wide modal launched from the `[preview]` button on the
# channel edit form. Top-nav `[desktop][mobile][tv]` toggles which
# layout panel is visible; the component renders all three panels
# concurrently (only one carries the `active` class at a time).
#
# `pending:` is an attribute-overlay Hash. Form-input edits stream
# in via the `channel-preview` Stimulus controller (debounced 300ms);
# the controller issues `GET /channels/:id/preview?...` and the
# server re-renders this component with the dirty params merged
# over the persisted `Channel`. Lookups go through `resolve(:attr)`
# so the override path is identical for every field (`title`,
# `handle`, `banner_url`, `avatar_url`, `description`, `links`).
class ChannelPreviewComponent < ViewComponent::Base
  LAYOUTS = %w[desktop mobile tv].freeze
  DEFAULT_LAYOUT = "desktop".freeze
  VIDEO_ROW_SIZE = 6
  REAL_VIDEO_THRESHOLD = 6

  attr_reader :channel, :pending

  def initialize(channel:, pending: {}, active_layout: DEFAULT_LAYOUT)
    @channel = channel
    # Stringify keys so callers can pass either symbols (from
    # internal Rails code) or strings (from `request.query_parameters`,
    # which always hands back string keys).
    @pending = (pending || {}).stringify_keys
    @active_layout = LAYOUTS.include?(active_layout.to_s) ? active_layout.to_s : DEFAULT_LAYOUT
  end

  def active_layout
    @active_layout
  end

  # Resolves a single channel attribute, preferring the pending
  # override when present (treat blank-string overrides as "user
  # cleared the field" → fall through to the original column value
  # only when the override key was not supplied at all). The links
  # array branch handles its own dirty-detection because empty
  # arrays are a meaningful state.
  def resolve(attr)
    key = attr.to_s
    return @pending[key] if @pending.key?(key)

    channel.public_send(attr)
  end

  def resolved_title
    value = resolve(:title).to_s.strip
    value.empty? ? "untitled channel" : value
  end

  def resolved_handle
    resolve(:handle).to_s.strip
  end

  def resolved_description
    resolve(:description).to_s.strip
  end

  def resolved_banner_url
    resolve(:banner_url).to_s.strip
  end

  def resolved_avatar_url
    resolve(:avatar_url).to_s.strip
  end

  # The pending key may be a JSON-encoded array (when shipped as a
  # query param) or a Ruby array (when called inline). Other types
  # collapse to an empty array so the view never crashes on a stale
  # bad override.
  def resolved_links
    raw = pending.key?("links") ? pending["links"] : channel.links
    case raw
    when Array
      raw.select { |e| e.is_a?(Hash) }
    when String
      parsed = safe_parse_json(raw)
      parsed.is_a?(Array) ? parsed.select { |e| e.is_a?(Hash) } : []
    else
      []
    end
  end

  def formatted_subscriber_count
    return "Hidden" if channel.hidden_subscriber_count?
    return "—" if channel.subscriber_count.nil?

    helpers.number_to_human(channel.subscriber_count, precision: 2)
  end

  def avatar_placeholder_glyph
    first = resolved_title.to_s.strip[0]
    (first || "?").upcase
  end

  # Returns one of three video-row branches:
  #   - `[:real, [Video, ...]]` — channel has ≥6 titled real videos.
  #   - `[:static, [{title:, thumbnail:}, ...]]` — fall back to
  #     `PreviewHelper.random_video_thumbnail` + sampled titles.
  #   - `[:empty, []]` — the thumbnails directory is empty AND the
  #     channel has no real videos; renders the muted empty-state
  #     line per D8.
  def video_row
    titled_count = channel.videos.where.not(title: nil).count
    if titled_count >= REAL_VIDEO_THRESHOLD
      videos = channel.videos
                      .where.not(title: nil)
                      .order(Arel.sql("star DESC, COALESCE(published_at, created_at) DESC"))
                      .limit(VIDEO_ROW_SIZE)
                      .to_a
      return [ :real, videos ]
    end

    if PreviewHelper.available_thumbnail_files.empty?
      [ :empty, [] ]
    else
      titles = PreviewHelper.sample_titles(count: VIDEO_ROW_SIZE, seed: channel.id || 0)
      pseudo = Array.new(VIDEO_ROW_SIZE) do |i|
        {
          title: titles[i],
          thumbnail: PreviewHelper.random_video_thumbnail(seed: i + (channel.id || 0))
        }
      end
      [ :static, pseudo ]
    end
  end

  # Pre-compute the layout list with `active` semantics so the view
  # can iterate without duplicating the conditional logic.
  def layouts
    LAYOUTS.map { |name| [ name, name == active_layout ] }
  end

  private

  def safe_parse_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end
end
