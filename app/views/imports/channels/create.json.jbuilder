json.import_jobs @enqueued do |job|
  json.id              job.id
  json.channel_id      job.channel_id
  json.status          job.status
  json.total_videos    job.total_videos
  json.imported_videos job.imported_videos
  json.failed_videos   job.failed_videos
  json.in_flight       YesNo.to_yes_no(job.in_flight?)
  json.url             "/imports/channels/#{job.id}"
end

json.errors @errors if @errors.present?
