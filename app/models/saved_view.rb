class SavedView < ApplicationRecord
  enum :kind, { channels: 0, videos: 1 }

  validates :kind, presence: true
  validates :url, presence: true, uniqueness: { scope: :kind }
  validates :name, presence: true

  scope :ordered, -> { order(position: :asc, created_at: :desc) }

  def display_name
    "#{kind.titleize}: #{name}"
  end

  def display_name_with_deletions
    labels = entity_labels
    return name if labels.empty?

    parts = labels.map { |l| l[:deleted] ? "[deleted]" : l[:title] }
    parts.join(" + ")
  end

  def entity_labels
    ids = extract_ids_from_url
    return [] if ids.empty?

    model_class = kind == "channels" ? Channel : Video
    existing = model_class.where(id: ids).index_by(&:id)

    ids.map do |id|
      entity = existing[id.to_i]
      { id: id, title: label_for(entity) || "[deleted]", deleted: entity.nil? }
    end
  end

  private

  def label_for(entity)
    return nil if entity.nil?

    # Phase 7 Path A2 — both Channel and Video are thin
    # YouTube-reference records now. The id is the only stable
    # display attribute on either class.
    case kind
    when "channels" then entity.id.to_s
    when "videos"   then entity.id.to_s
    end
  end

  def extract_ids_from_url
    uri = URI.parse(url)
    if uri.path.match?(%r{/panes\z})
      params = Rack::Utils.parse_query(uri.query.to_s)
      params["ids"].to_s.split(/[\s,+]+/).reject(&:blank?)
    elsif (match = uri.path.match(%r{/(\d+)\z}))
      [ match[1] ]
    else
      []
    end
  rescue URI::InvalidURIError
    []
  end
end
