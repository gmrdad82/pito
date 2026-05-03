# End-to-end verification of the yes/no boundary refactor.
# Run via:  bin/rails runner _temp/yes_no_e2e.rb
#
# Wraps mutations in a transaction that is rolled back at the end so
# development data is not modified.

require "json"

# Disable CSRF for the test session (we're not running a real browser).
ActionController::Base.allow_forgery_protection = false

results = []

ApplicationRecord.transaction do
  tenant = Tenant.first || Tenant.create!(name: "e2e-temp")
  channel = Channel.create!(
    tenant: tenant,
    channel_url: "https://www.youtube.com/channel/UCe2eYesNoTestAAAAAAAAAA"
  )
  starred = Channel.create!(
    tenant: tenant,
    channel_url: "https://www.youtube.com/channel/UCe2eStarTestAAAAAAAAAAA",
    star: true
  )

  # ----------------------------------------------------------------
  # 1. Decorator output uses yes/no strings
  # ----------------------------------------------------------------
  json = ChannelDecorator.new(channel).as_summary_json
  results << [
    "ChannelDecorator#as_summary_json[:star] is 'no' (not false)",
    json[:star] == "no"
  ]
  results << [
    "ChannelDecorator output contains no raw booleans",
    [ json[:star], json[:connected], json[:syncing] ].all? { |v| %w[yes no].include?(v) }
  ]

  starred_json = ChannelDecorator.new(starred).as_summary_json
  results << [
    "starred channel decorator emits 'yes'",
    starred_json[:star] == "yes"
  ]

  detail = ChannelDecorator.new(starred).as_detail_json
  results << [
    "as_detail_json carries yes/no through merge",
    detail[:star] == "yes" && detail[:connected] == "no"
  ]

  # ----------------------------------------------------------------
  # 2. Controller filter via Rack::Test
  # ----------------------------------------------------------------
  require "rack/test"
  session = Rack::Test::Session.new(Rails.application)
  # Bypass HostAuthorization in development
  session.header "Host", "app.pitomd.com"

  session.get "/channels", { star: "yes" }
  body_yes = session.last_response.body
  results << [
    "GET /channels?star=yes filters to starred only",
    session.last_response.status == 200 \
      && body_yes.include?(starred.channel_url) \
      && !body_yes.include?(channel.channel_url)
  ]

  session.get "/channels", { star: "1" }
  body_one = session.last_response.body
  results << [
    "GET /channels?star=1 does NOT filter (legacy values rejected)",
    session.last_response.status == 200 \
      && body_one.include?(starred.channel_url) \
      && body_one.include?(channel.channel_url)
  ]

  session.get "/channels", { star: "true" }
  body_true = session.last_response.body
  results << [
    "GET /channels?star=true does NOT filter",
    session.last_response.status == 200 \
      && body_true.include?(starred.channel_url) \
      && body_true.include?(channel.channel_url)
  ]

  # ----------------------------------------------------------------
  # 3. JSON API
  # ----------------------------------------------------------------
  session.get "/channels.json"
  data = JSON.parse(session.last_response.body)
  results << [
    "GET /channels.json: every row has yes/no string flags",
    session.last_response.status == 200 \
      && data.all? { |row| %w[yes no].include?(row["star"]) }
  ]

  session.patch "/channels/#{channel.id}.json",
    { channel: { star: "yes" } }.to_json,
    "CONTENT_TYPE" => "application/json"
  resp = JSON.parse(session.last_response.body)
  results << [
    "PATCH /channels/:id.json with star='yes' => 200 + 'yes' echoed",
    session.last_response.status == 200 && resp["star"] == "yes"
  ]

  session.patch "/channels/#{channel.id}.json",
    { channel: { star: true } }.to_json,
    "CONTENT_TYPE" => "application/json"
  results << [
    "PATCH /channels/:id.json with star=true (raw bool) => 422",
    session.last_response.status == 422
  ]

  session.patch "/channels/#{channel.id}.json",
    { channel: { star: "1" } }.to_json,
    "CONTENT_TYPE" => "application/json"
  results << [
    "PATCH /channels/:id.json with star='1' (legacy) => 422",
    session.last_response.status == 422
  ]

  # ----------------------------------------------------------------
  # 4. MCP tools
  # ----------------------------------------------------------------
  res = Mcp::Tools::UpdateChannel.call(id: channel.id, star: "no")
  results << [
    "Mcp::Tools::UpdateChannel(star: 'no') succeeds, output uses 'no'",
    !res.to_h[:isError] && res.content.first[:text].include?('"star": "no"')
  ]

  res = Mcp::Tools::UpdateChannel.call(id: channel.id, star: true)
  results << [
    "Mcp::Tools::UpdateChannel(star: true) is rejected",
    res.to_h[:isError] == true
  ]

  res = Mcp::Tools::UpdateChannel.call(id: channel.id, star: "1")
  results << [
    "Mcp::Tools::UpdateChannel(star: '1') is rejected",
    res.to_h[:isError] == true
  ]

  res = Mcp::Tools::ListChannels.call(star: "yes")
  data = JSON.parse(res.content.first[:text])
  results << [
    "Mcp::Tools::ListChannels(star: 'yes') filters and outputs yes/no",
    !res.to_h[:isError] \
      && data.all? { |r| %w[yes no].include?(r["star"]) } \
      && data.any? { |r| r["id"] == starred.id }
  ]

  res = Mcp::Tools::ListChannels.call(star: true)
  results << [
    "Mcp::Tools::ListChannels(star: true) is rejected",
    res.to_h[:isError] == true
  ]

  res = Mcp::Tools::DeleteRecords.call(type: "channel", ids: [ channel.id ], confirm: "no")
  results << [
    "Mcp::Tools::DeleteRecords(confirm: 'no') returns preview",
    !res.to_h[:isError] && res.content.first[:text].include?("Preview only")
  ]

  res = Mcp::Tools::DeleteRecords.call(type: "channel", ids: [ channel.id ], confirm: true)
  results << [
    "Mcp::Tools::DeleteRecords(confirm: true) is rejected",
    res.to_h[:isError] == true
  ]

  res = Mcp::Tools::SyncRecords.call(type: "channel", ids: [ channel.id ], confirm: true)
  results << [
    "Mcp::Tools::SyncRecords(confirm: true) is rejected",
    res.to_h[:isError] == true
  ]

  # MCP resource — app status — search_healthy is yes/no
  status_payload = Mcp::Resources::AppStatus.read("pito://status").first
  status_data = JSON.parse(status_payload[:text])
  results << [
    "pito://status emits search_healthy as yes/no",
    %w[yes no].include?(status_data["search_healthy"])
  ]

  raise ActiveRecord::Rollback
end

# ----------------------------------------------------------------------
# Print results
# ----------------------------------------------------------------------
puts ""
puts "=== yes/no boundary E2E results ==="
all_ok = true
results.each do |label, ok|
  marker = ok ? "OK  " : "FAIL"
  all_ok &&= ok
  puts "#{marker}  #{label}"
end
puts ""
puts(all_ok ? "all checks passed" : "FAILURES present")
exit(all_ok ? 0 : 1)
