# frozen_string_literal: true

class Video
  # Builds the multi-field text embedded for a Video — the single
  # source of truth shared by `Video::EmbeddingIndexer` and any bulk path (so
  # the per-record and bulk paths can never drift). Mirrors `Game::EmbedText`.
  #
  # Fields (em-dash joined, blank slots skipped): title · description · tags ·
  # category. Category is the YouTube numeric `categoryId` mapped to a name via
  # a static table (no extra API call — the IDs are stable/well-known); an
  # unknown id is skipped rather than guessed.
  module EmbedText
    SEPARATOR = " — "

    # YouTube Data API video category IDs → human names. Stable set; an id not
    # listed here is omitted from the embed text.
    YOUTUBE_CATEGORIES = {
      "1"  => "Film & Animation",
      "2"  => "Autos & Vehicles",
      "10" => "Music",
      "15" => "Pets & Animals",
      "17" => "Sports",
      "18" => "Short Movies",
      "19" => "Travel & Events",
      "20" => "Gaming",
      "21" => "Videoblogging",
      "22" => "People & Blogs",
      "23" => "Comedy",
      "24" => "Entertainment",
      "25" => "News & Politics",
      "26" => "Howto & Style",
      "27" => "Education",
      "28" => "Science & Technology",
      "29" => "Nonprofits & Activism",
      "30" => "Movies",
      "31" => "Anime/Animation",
      "32" => "Action/Adventure",
      "33" => "Classics",
      "34" => "Comedy",
      "35" => "Documentary",
      "36" => "Drama",
      "37" => "Family",
      "38" => "Foreign",
      "39" => "Horror",
      "40" => "Sci-Fi/Fantasy",
      "41" => "Thriller",
      "42" => "Shorts",
      "43" => "Shows",
      "44" => "Trailers"
    }.freeze

    module_function

    def call(video)
      parts = []
      parts << video.title.to_s.strip if video.title.present?
      parts << video.description.to_s.strip if video.description.present?
      parts << labelled("tags", Array(video.tags))
      parts << category_phrase(video)
      parts.reject(&:blank?).join(SEPARATOR)
    end

    def labelled(label, values)
      list = Array(values).map { |v| v.to_s.strip }.reject(&:blank?).uniq
      return "" if list.empty?

      "#{label}: #{list.join(', ')}"
    end

    def category_phrase(video)
      name = YOUTUBE_CATEGORIES[video.category_id.to_s]
      name.present? ? "category: #{name}" : ""
    end
  end
end
