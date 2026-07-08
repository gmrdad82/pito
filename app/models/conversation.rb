# frozen_string_literal: true

class Conversation < ApplicationRecord
  has_many :turns, -> { order(:position) }, dependent: :destroy
  has_many :events, -> { order(:position) }, dependent: :destroy

  before_create :set_uuid
  before_create :set_default_title

  normalizes :uuid, with: ->(value) { value&.downcase }

  validates :uuid, uniqueness: { case_sensitive: true }

  # ── Source (G130): app scrollback vs the read-only MCP anchor ────────────────
  # "app" — the owner's real conversations (sidebar, resume, auto-purge, singleton).
  # "mcp" — the ONE anchor the read-only MCP Executor dispatches against; context
  # only, it never gains events and never appears in any app-facing listing.
  SOURCES = %w[app mcp].freeze
  validates :source, inclusion: { in: SOURCES }

  # ── Routing ─────────────────────────────────────────────────
  # Use the UUID in URLs instead of the numeric primary key.
  def to_param
    uuid
  end

  # ── Display ─────────────────────────────────────────────────
  def display_name
    title.presence || "Unnamed #{id}"
  end

  # True when the conversation carries a user-chosen name (i.e. not the
  # auto-assigned "Unnamed N" default). Drives the purple name shown in the
  # chatbox filter row.
  def named?
    title.present? && !title.match?(/\AUnnamed\b/)
  end

  # True when the conversation still carries its AUTO-GENERATED default title
  # ("Unnamed <N>") or no title at all — i.e. the user never named it. STRICTER
  # than `!named?`: a user-chosen title that merely starts with "Unnamed" (e.g.
  # "Unnamed thoughts") is NOT the default and returns false, so it is protected.
  # Drives the nightly auto-purge (item 15): only the literal default is purgeable.
  def default_title?
    title.blank? || title.match?(/\AUnnamed \d+\z/)
  end

  # True while an async delete is in flight — the sidebar renders this row as the
  # shimmering-dots placeholder instead of the title/timestamp (DeleteConversationJob
  # clears it by destroying the record). Persisted, so a mid-delete sidebar reopen
  # still shows the dots.
  def deleting? = deleting_at.present?

  # Conversations with an in-flight async delete.
  def self.deleting = where.not(deleting_at: nil)

  # Event kinds that count toward the CONTEXT meter (item 7): only distinct
  # backend MESSAGES — :system, :enhanced, :confirmation. Excludes thinking/echo/
  # error, AND the *_follow_up / mutate re-renders ("appends don't count").
  CONTEXT_KINDS = %w[system enhanced confirmation].freeze

  # Count of distinct messages filling the context meter.
  def context_event_count
    events.where(kind: CONTEXT_KINDS).count
  end

  # ── Query helpers ────────────────────────────────────────────
  # The primary APP conversation (source-scoped so it can never grab the MCP
  # anchor). Callers that mean "the owner's current conversation" use this.
  def self.singleton
    where(source: "app").first_or_create!
  end

  # The single MCP anchor (source: "mcp"). The read-only Executor needs a
  # persisted conversation id (handle minting, scope/period state) but never
  # persists its events, so this row stays empty forever. Excluded from
  # singleton / by_recent_activity, so it never leaks into the app scrollback,
  # the resume sidebar, or the nightly auto-purge.
  def self.mcp_anchor
    where(source: "mcp").first_or_create!
  end

  # Returns APP conversations ordered by last activity (most recent first).
  # "Last activity" = MAX(events.created_at) for the conversation, falling
  # back to the conversation's own created_at when it has no events.
  # Each returned record has a `last_activity_at` virtual attribute. The MCP
  # anchor is excluded (source: "app"), so it never surfaces in resume/purge.
  def self.by_recent_activity
    where(source: "app")
      .left_joins(:events)
      .select(
        "conversations.*",
        "COALESCE(MAX(events.created_at), conversations.created_at) AS last_activity_at"
      )
      .group("conversations.id")
      .order("last_activity_at DESC")
  end

  # Returns a hash with two keys:
  #   :recent — conversations whose last_activity_at is within 24 h of the
  #              most-recent conversation's last_activity_at (i.e. relative to
  #              the newest, NOT relative to now).
  #   :older  — the rest, ordered most-recent first.
  #
  # Edge cases:
  #   - Empty collection → both buckets are [].
  #   - Single conversation → it lands in :recent; :older is [].
  #   - All within 24 h → all land in :recent; :older is [].
  def self.recency_groups
    all_ordered = by_recent_activity.to_a
    return { recent: [], older: [] } if all_ordered.empty?

    cutoff = all_ordered.first.last_activity_at - 24.hours
    recent, older = all_ordered.partition { |c| c.last_activity_at > cutoff }
    { recent: recent, older: older }
  end

  # Conversations eligible for the nightly auto-purge (item 15): still carrying
  # the AUTO-DEFAULT title ("Unnamed <N>"/blank) AND no activity in `older_than`
  # (default 30 days). "Activity" = last_activity_at (COALESCE(MAX(events.created_at),
  # created_at)), the same recency the sidebar shows. SQL filters the date via
  # HAVING; the default-title test is applied in Ruby via `default_title?` — only
  # the literal default is matched, so ANYTHING the user typed (even a title that
  # starts with "Unnamed") is protected and can NEVER be selected for deletion.
  # Returns an Array of ::Conversation.
  def self.purgeable(older_than: 30.days.ago)
    by_recent_activity
      .having("COALESCE(MAX(events.created_at), conversations.created_at) < ?", older_than)
      .to_a
      .select(&:default_title?)
  end

  # Exact title match, case-insensitive — for `/resume <name>`. nil when blank/none.
  def self.find_by_title_ci(name)
    norm = name.to_s.strip
    return nil if norm.blank?

    where("LOWER(title) = LOWER(?)", norm).first
  end

  # Up to `limit` conversations whose title is fuzzy-close to `name` (typo
  # recovery for `/resume`), excluding an exact match, ordered by edit distance
  # then recency. Empty when nothing is close enough (→ omit the suggestions block).
  def self.similar_titles(name, limit: 5)
    query = name.to_s.strip.downcase
    return [] if query.blank?

    by_recent_activity.to_a.filter_map { |c|
      title = c.title.to_s.strip
      next if title.blank? || title.downcase == query

      distance  = Pito::Fuzzy.levenshtein(query, title.downcase)
      threshold = [ [ query.length, title.length ].max / 3, 2 ].max
      [ c, distance ] if distance <= threshold
    }.sort_by { |(c, distance)| [ distance, -c.last_activity_at.to_i ] }
      .first(limit)
      .map(&:first)
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def set_default_title
    self.title ||= "Unnamed #{self.class.count + 1}"
  end
end
