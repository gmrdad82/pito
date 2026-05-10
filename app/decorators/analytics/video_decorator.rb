# Phase 13.3 — Video decorator for the analytics dashboard.
# Same shape as `Analytics::ChannelDecorator` — analytics-aware
# lookups for the views.
module Analytics
  class VideoDecorator < Draper::Decorator
    delegate_all

    def window_summary(window)
      VideoWindowSummary.find_by(video_id: id, window: window)
    end

    def daily_for_window(start_date, end_date)
      VideoDaily
        .for_window(start_date, end_date)
        .where(video_id: id)
        .ordered_by_date
    end

    # Retention curve buckets ordered by `elapsed_ratio_bucket` so
    # the line chart paints left-to-right (0.00 → 0.99).
    def retention
      VideoRetention.where(video_id: id).ordered_by_bucket
    end

    def country_breakdown_for_window(start_date, end_date, limit: 25)
      VideoDailyByCountry
        .where(video_id: id, date: start_date..end_date)
        .group(:country_code)
        .order(Arel.sql("SUM(views) DESC"))
        .limit(limit)
        .sum(:views)
    end

    def device_breakdown_for_window(start_date, end_date)
      VideoDailyByDeviceType
        .where(video_id: id, date: start_date..end_date)
        .group(:device_type)
        .sum(:views)
    end

    def os_breakdown_for_window(start_date, end_date)
      VideoDailyByOperatingSystem
        .where(video_id: id, date: start_date..end_date)
        .group(:operating_system)
        .sum(:views)
    end

    def traffic_source_breakdown_for_window(start_date, end_date)
      VideoDailyByTrafficSource
        .where(video_id: id, date: start_date..end_date)
        .group(:traffic_source_type)
        .sum(:views)
    end

    def subscribed_status_breakdown_for_window(start_date, end_date)
      VideoDailyBySubscribedStatus
        .where(video_id: id, date: start_date..end_date)
        .group(:subscribed_status)
        .sum(:views)
    end

    def demographics_for_window(start_date, end_date)
      VideoDailyByAgeGroupGender
        .where(video_id: id, date: start_date..end_date)
        .group(:age_group, :gender)
        .sum(:viewer_percentage)
    end
  end
end
