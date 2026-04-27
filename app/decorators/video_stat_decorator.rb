class VideoStatDecorator < ApplicationDecorator
  def as_json_entry
    {
      date: date.iso8601,
      views: views,
      likes: likes,
      comments: comments,
      shares: shares,
      watch_time_minutes: watch_time_minutes
    }
  end
end
