# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Pure-function service. Compares a Pito-side `Channel` to a YouTube-
# side normalized payload (snake_case symbolized Hash from
# `Youtube::Client#fetch_channel`) and returns the differing fields as
#
#   { "field" => { "pito" => <pito_value>, "youtube" => <yt_value> } }
#
# The hash is always String-keyed (matches the jsonb shape stored on
# `ChannelDiff#field_diffs`).
#
# Whitelist of fields that count as diffs (locked spec list):
#
#   - title, handle, description, country, default_language
#   - keywords (sorted-set comparison — order changes do not diff)
#   - links (sorted by JSON-stringified tuple)
#   - banner_url, avatar_url, watermark_url (CDN-rotation filtered)
#   - watermark_timing, watermark_offset_ms
#
# Statistics (`subscriber_count`, `view_count`, `video_count`) are
# **display-only** — refreshed silently on every cron pass by the
# orchestrating job; never contribute to the diff.
#
# Normalization rules (locked decisions):
#
#   - Q-WHITESPACE: leading / trailing whitespace stripped; internal
#     runs collapsed to a single space before string comparison.
#   - Nil / "" / [] are equivalent → no diff.
#   - Q-CDN: banner / avatar / watermark URLs are normalized by
#     stripping the query string + leading CDN host before comparison.
#     YouTube re-issues CDN URLs without semantic change; rotating
#     hosts / query strings does NOT diff.
#   - Keywords compare as a sorted set of tokens (whitespace-split).
#   - Links compare as a sorted array of `{ title, url }` tuples.
#
# No side effects: the computer never writes to the channel, never
# enqueues jobs, never logs. The job orchestrates persistence + I/O.
module Channels
  class DiffComputer
    # Diffable fields per locked whitelist.
    DIFF_FIELDS = %w[
      title
      handle
      description
      country
      default_language
      keywords
      links
      banner_url
      avatar_url
      watermark_url
      watermark_timing
      watermark_offset_ms
    ].freeze

    # Asset URL fields → CDN-rotation filtered (Q-CDN).
    ASSET_URL_FIELDS = %w[banner_url avatar_url watermark_url].freeze

    # CDN host stripping: drop leading scheme + host (`https://yt3.ggpht.com`).
    CDN_HOST_PREFIX = %r{\Ahttps?://[^/]+}

    def self.call(channel, payload)
      new(channel, payload).call
    end

    def initialize(channel, payload)
      @channel = channel
      @payload = symbolize(payload || {})
    end

    def call
      DIFF_FIELDS.each_with_object({}) do |field, diff|
        pito_value = pito_side(field)
        youtube_value = youtube_side(field)

        next if values_equivalent?(field, pito_value, youtube_value)

        diff[field] = {
          "pito"    => normalize_for_storage(pito_value),
          "youtube" => normalize_for_storage(youtube_value)
        }
      end
    end

    private

    # Coerce payload keys to symbols recursively so callers may pass
    # either `Symbol`- or `String`-keyed hashes (the YouTube client
    # returns Symbol; some test fixtures pass String).
    def symbolize(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize(v) }
      when Array
        value.map { |v| symbolize(v) }
      else
        value
      end
    end

    def pito_side(field)
      @channel.public_send(field) if @channel.respond_to?(field)
    end

    def youtube_side(field)
      @payload[field.to_sym]
    end

    def values_equivalent?(field, a, b)
      case field
      when "keywords"
        keywords_set(a) == keywords_set(b)
      when "links"
        links_set(a) == links_set(b)
      when *ASSET_URL_FIELDS
        normalize_asset_url(a) == normalize_asset_url(b)
      when "watermark_offset_ms"
        coerce_integer(a) == coerce_integer(b)
      else
        normalize_string(a) == normalize_string(b)
      end
    end

    # Convert a keywords value (String of whitespace-separated tokens,
    # or Array) into a sorted Set-like Array for order-insensitive
    # comparison. Empty / nil normalize to [].
    def keywords_set(value)
      tokens = case value
      when nil  then []
      when Array then value.flat_map { |v| v.to_s.split }
      else value.to_s.split
      end
      tokens.map(&:strip).reject(&:empty?).sort
    end

    # Compare links as a sorted set of `{title, url}` tuples. JSON-
    # serialize each tuple for stable sort. Nil / [] normalize to [].
    def links_set(value)
      Array(value).filter_map do |entry|
        next nil unless entry.is_a?(Hash)
        title = entry["title"] || entry[:title]
        url   = entry["url"]   || entry[:url]
        next nil if title.nil? && url.nil?
        { "title" => title.to_s, "url" => url.to_s }
      end.sort_by { |h| [ h["title"], h["url"] ] }
    end

    # Strip CDN host + query string before comparing asset URLs.
    # `nil` / `""` collapse to nil so the
    # "channel that never had a banner" stays in-sync with a YouTube
    # response that omits banner_external_url.
    def normalize_asset_url(value)
      return nil if value.nil? || value.to_s.strip.empty?
      str = value.to_s
      # Drop query string.
      str = str.split("?", 2).first.to_s
      # Drop CDN host prefix — keeps the path component, which is the
      # stable identifier of the underlying asset. Query strings and
      # CDN hosts rotate; the path stays stable across re-issuances.
      str = str.sub(CDN_HOST_PREFIX, "")
      str
    end

    # Whitespace-normalize strings: strip + collapse internal runs
    # (locked Q-WHITESPACE). nil / "" both collapse to nil so the
    # "never had a description" channel stays in-sync with a payload
    # that omits the field.
    def normalize_string(value)
      return nil if value.nil?
      str = value.to_s.gsub(/\s+/, " ").strip
      str.empty? ? nil : str
    end

    def coerce_integer(v)
      return nil if v.nil? || v.to_s.strip.empty?
      Integer(v.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Serialize a Ruby value into a jsonb-safe form for the
    # `ChannelDiff#field_diffs` storage. Arrays / hashes pass through;
    # nil passes through; everything else is `to_s`'d defensively.
    def normalize_for_storage(v)
      case v
      when nil, true, false, Numeric, String, Array, Hash then v
      else v.to_s
      end
    end
  end
end
