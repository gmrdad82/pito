json.import_job do
  json.id              @import_job.id
  json.channel_id      @import_job.channel_id
  json.status          @import_job.status
  json.total_videos    @import_job.total_videos
  json.imported_videos @import_job.imported_videos
  json.failed_videos   @import_job.failed_videos
  json.in_flight       YesNo.to_yes_no(@import_job.in_flight?)
  json.started_at      @import_job.started_at
  json.completed_at    @import_job.completed_at
  json.error_payload   @import_job.error_payload
  json.url             "/imports/channels/#{@import_job.id}"
end

json.candidate_videos @candidate_videos do |video|
  json.id               video.id
  json.youtube_video_id video.youtube_video_id
  json.title            video.title
  json.duration_seconds video.duration_seconds
  json.category_id      video.category_id
end
