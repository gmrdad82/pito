# frozen_string_literal: true

# SAMPLE — this module will be replaced when real data is wired in Plan 2+.
module Pito
  module Sample
    module GameDetail
      def self.game
        {
          title: "Hollow Knight",
          subtitle_date: "2026-05-18",
          sections: [
            {
              title_key: "pito.sidebar.section.overview",
              rows: [
                { label: "Genre",          value: "Metroidvania" },
                { label: "Released",        value: "2017-02-24" },
                { label: "Steam reviews",   value: "97% positive" },
                { label: "Imported",        value: "8 days ago" },
                { label: "Developer",       value: "Team Cherry" },
                { label: "Publisher",       value: "Team Cherry" },
                { label: "Platforms",       value: "Windows, macOS, Linux, Switch, PS4, Xbox" },
                { label: "Price",           value: "$14.99" },
                { label: "Play time",       value: "25-40 hours" },
                { label: "Completion",      value: "112%" },
                { label: "Achievements",    value: "34/34" },
                { label: "Rating",          value: "9.5/10" }
              ]
            },
            {
              title_key: "pito.sidebar.section.channels",
              rows: [
                { label: "@gmrdad82",         value: "3 videos",  label_color: :cyan },
                { label: "@gmrdad82-vlog",    value: "1 video",   label_color: :cyan },
                { label: "@gmrdad82-shorts",  value: "12 videos", label_color: :cyan },
                { label: "@gmrdad82-clips",   value: "8 videos",  label_color: :cyan },
                { label: "@gmrdad82-live",    value: "5 videos",  label_color: :cyan },
                { label: "@gmrdad82-archives", value: "0 videos", label_color: :cyan }
              ]
            },
            {
              title_key: "pito.sidebar.section.top_videos",
              type: :top_videos,
              rows: [
                { date: "2026-05-24", title: "How to play Hollow Knight",          views: "12k views" },
                { date: "2026-05-21", title: "Hollow Knight charms tier list",      views: "8k views" },
                { date: "2026-05-19", title: "Speedrun guide",                     views: "45k views" },
                { date: "2026-05-17", title: "All boss fights no damage",          views: "67k views" },
                { date: "2026-05-15", title: "Hidden areas you missed",            views: "23k views" },
                { date: "2026-05-12", title: "Best build for each area",           views: "31k views" },
                { date: "2026-05-10", title: "Nightmare King Grimm guide",          views: "89k views" },
                { date: "2026-05-08", title: "Pantheon of Hallownest full run",     views: "156k views" },
                { date: "2026-05-06", title: "Godmaster DLC complete guide",       views: "42k views" },
                { date: "2026-05-03", title: "Steel Soul mode tips and tricks",    views: "18k views" },
                { date: "2026-05-01", title: "Path of Pain walkthrough",           views: "73k views" }
              ]
            },
            {
              title_key: "pito.sidebar.section.tags",
              type: :tags,
              tags: "metroidvania, indie, souls-like, 2D platformer"
            },
            {
              title_key: "pito.sidebar.section.recommendation",
              type: :paragraph,
              text: "Based on neighbor channel analysis, consider a Hollow Knight: Silksong preview video for @gmrdad82-shorts — audience overlap is 72%."
            },
            {
              title_key: "pito.sidebar.section.quick_commands",
              type: :commands,
              commands: [
                "/import-game-videos Hollow Knight",
                "/channels-for-game Hollow Knight",
                "/export-game-data Hollow Knight",
                "/compare Hollow Knight vs Silksong",
                "/analyze-tags Hollow Knight",
                "/recommend-similar Hollow Knight",
                "/top-clips Hollow Knight",
                "/audience-overlap Hollow Knight",
                "/trending Hollow Knight",
                "/summarize Hollow Knight"
              ]
            }
          ]
        }
      end
    end
  end
end
