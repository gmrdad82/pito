json.channels @channels do |channel|
  in_flight_job = channel.in_flight_import_job

  json.id          channel.id
  json.slug        channel.url_slug
  json.label       channel.title.presence || channel.url_slug || "channel ##{channel.id}"
  json.channel_url channel.channel_url
  json.connected   YesNo.to_yes_no(channel.youtube_connection_id.present?)
  json.in_flight   YesNo.to_yes_no(in_flight_job.present?)
  if in_flight_job
    json.in_flight_job_id in_flight_job.id
  end
end
