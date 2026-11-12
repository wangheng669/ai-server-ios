# frozen_string_literal: true

require_relative "testflight-processing-notify"

APP_ID = "6793626100"
GROUP_ID = "e5f14909-f036-467c-aecb-4ea301c3dfd2"
TESTER_ID = "b219838f-16d1-466f-8d7f-b53b16f8b5da"
MARKETING_VERSION = "1.0.23"
BUILD_NUMBER = "11"

class FocusTestFlightClient < TestFlightProcessing::Client
  def delete_tester(tester_id)
    uri = URI.join(TestFlightProcessing::API_BASE, "/v1/betaTesters/#{tester_id}")
    request = Net::HTTP::Delete.new(uri)
    request["Authorization"] = "Bearer #{token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    raise "Apple declined deletion of the TestFlight record (HTTP #{response.code})" unless %w[202 204].include?(response.code)
  end

  def enroll_by_email(email, group_id)
    uri = URI.join(TestFlightProcessing::API_BASE, "/v1/betaTesters")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(data: {
      type: "betaTesters",
      attributes: { email: email },
      relationships: { betaGroups: { data: [{ type: "betaGroups", id: group_id }] } }
    })
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    payload = JSON.parse(response.body) rescue {}
    if response.code == "201"
      return payload.fetch("data").fetch("id")
    end

    errors = Array(payload["errors"]).map do |error|
      [error["code"], error["detail"].to_s.gsub(/[^\s]+@[^\s]+/, "[email]")[0, 220]]
    end
    raise "Apple declined internal enrollment by email (HTTP #{response.code}: #{JSON.generate(errors)})"
  end

  def associate_build(group_id, build_id)
    uri = URI.join(TestFlightProcessing::API_BASE, "/v1/betaGroups/#{group_id}/relationships/builds")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(data: [{type: "builds", id: build_id}])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    raise "Could not associate build with internal group (HTTP #{response.code})" unless response.code == "204"
  end

  def assign_individual_tester(build_id, tester_id)
    uri = URI.join(TestFlightProcessing::API_BASE, "/v1/builds/#{build_id}/relationships/individualTesters")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(data: [{type: "betaTesters", id: tester_id}])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    return if response.code == "204"

    payload = JSON.parse(response.body) rescue {}
    errors = Array(payload["errors"]).map do |error|
      {code: error["code"], detail: error["detail"].to_s.gsub(/[^\s]+@[^\s]+/, "[email]")[0, 250]}
    end
    puts JSON.generate(individual_assignment: "DECLINED", http_status: response.code, errors: errors)
    exit 1
  end

  def change_tester_membership(method, path, tester_id)
    uri = URI.join(TestFlightProcessing::API_BASE, path)
    request = method.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(data: [{type: "betaTesters", id: tester_id}])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) do |http|
      http.request(request)
    end
    return response.code if %w[202 204].include?(response.code)

    payload = JSON.parse(response.body) rescue {}
    codes = Array(payload["errors"]).map { |error| error["code"] }
    raise "Apple returned HTTP #{response.code} for #{request.method}: #{codes.join(", ")}"
  end

  def resend_invitation(app_id, tester_id)
    uri = URI.join(TestFlightProcessing::API_BASE, "/v1/betaTesterInvitations")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(data: {
      type: "betaTesterInvitations",
      relationships: {
        app: {data: {type: "apps", id: app_id}},
        betaTester: {data: {type: "betaTesters", id: tester_id}}
      }
    })
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    payload = JSON.parse(response.body) rescue {}
    if response.code == "201"
      puts JSON.generate(invitation: "RESENT", http_status: 201, recipient: "26***@qq.com",
                         response_type: payload.dig("data", "type"))
    else
      errors = Array(payload["errors"]).map do |error|
        {code: error["code"], detail: error["detail"].to_s.gsub(/[^\s]+@[^\s]+/, "[email]")[0, 250]}
      end
      puts JSON.generate(invitation: "DECLINED", http_status: response.code, errors: errors)
      exit 1
    end
  end
end

def exact_build(api, app_id)
  response = api.builds(app_id)
  versions = response.fetch("included", []).to_h { |item| [item.fetch("id"), item.dig("attributes", "version")] }
  response.fetch("data").find do |item|
    item.dig("attributes", "version") == BUILD_NUMBER &&
      versions[item.dig("relationships", "preReleaseVersion", "data", "id")] == MARKETING_VERSION
  end
end

def group_status(api)
  group = api.get("/v1/betaGroups/#{GROUP_ID}", "fields[betaGroups]" => "isInternalGroup,hasAccessToAllBuilds")
    .dig("data", "attributes")
  testers = api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
                    "fields[betaTesters]" => "state,inviteType").fetch("data")
  tester = testers.find { |entry| entry.fetch("id") == TESTER_ID }
  {
    internal_group: group.fetch("isInternalGroup"),
    automatically_receives_builds: group.fetch("hasAccessToAllBuilds"),
    tester_count: testers.size,
    target_tester_state: tester&.dig("attributes", "state"),
    target_tester_invite_type: tester&.dig("attributes", "inviteType")
  }
end

def assigned?(api, build_id)
  builds = api.get("/v1/betaGroups/#{GROUP_ID}/builds", "limit" => "200",
                   "fields[builds]" => "version").fetch("data")
  builds.any? { |build| build.fetch("id") == build_id }
end

def processed_build(api, app_id)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1800
  loop do
    build = exact_build(api, app_id)
    state = build&.dig("attributes", "processingState")
    if state == "VALID"
      raise "Build is expired" if build.dig("attributes", "expired")
      return build.fetch("id")
    end
    raise "App Store Connect processing failed with #{state}" if %w[FAILED INVALID].include?(state)
    puts "Waiting for build #{MARKETING_VERSION} (#{BUILD_NUMBER}): #{state || "not listed"}"
    raise "Timed out waiting for Apple processing" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 15
  end
end

def masked_email(value)
  local, domain = value.to_s.split("@", 2)
  return nil unless domain && !local.empty?
  "#{local[0, 2]}***@#{domain}"
end

def read_diagnostics
  yield
rescue StandardError => error
  { error: error.message[/HTTP [0-9]{3}/] || error.class.name }
end

def audit_visibility(api, app_id, build)
  app = api.get("/v1/apps/#{app_id}", "fields[apps]" => "name,primaryLocale,bundleId")
    .dig("data", "attributes")
  groups = api.get("/v1/apps/#{app_id}/betaGroups", "limit" => "200",
                   "fields[betaGroups]" => "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled")
    .fetch("data")
  testers = api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
                    "fields[betaTesters]" => "email,state,inviteType").fetch("data")
  memberships = testers.map do |entry|
    attributes = entry.fetch("attributes")
    devices = read_diagnostics do
      response = api.get("/v1/betaTesters/#{entry.fetch("id")}/appDevices", "limit" => "20")
      response.fetch("data").map do |device|
        device.fetch("attributes").slice("model", "deviceModel", "deviceFamily", "platform", "osVersion")
      end
    end
    { prior_release_target: entry.fetch("id") == TESTER_ID, invitation: masked_email(attributes["email"]),
      state: attributes["state"], devices: devices }
  end
  beta_build = nil
  if build
    id = build.fetch("id")
    attributes = api.get("/v1/builds/#{id}", "fields[builds]" =>
      "version,processingState,expired,expirationDate,minOsVersion,buildAudienceType,usesNonExemptEncryption")
      .dig("data", "attributes")
    beta = api.get("/v1/builds/#{id}/buildBetaDetail").dig("data", "attributes")
    beta_build = { attributes: attributes, beta: beta, assigned_to_group: assigned?(api, id) }
  end
  puts JSON.generate(visibility_audit: {
    app: app, groups: groups.map { |entry| entry.fetch("attributes") },
    testers: memberships, build: beta_build
  })
end

def target_tester_in_group(api, group_id)
  testers = api.get("/v1/betaGroups/#{group_id}/betaTesters", "limit" => "200",
                    "fields[betaTesters]" => "state").fetch("data")
  testers.find { |tester| tester.fetch("id") == TESTER_ID }
end

def confirmed_tester(api)
  tester = api.get("/v1/betaTesters/#{TESTER_ID}", "fields[betaTesters]" => "email,inviteType")
    .dig("data", "attributes")
  raise "Recipient does not match the confirmed account" unless masked_email(tester.fetch("email")) == "26***@qq.com"
  tester
end

def audit_team_account(api, app_id)
  email = confirmed_tester(api).fetch("email").downcase
  users = api.get("/v1/users", "limit" => "200",
                  "fields[users]" => "username,roles,allAppsVisible,provisioningAllowed")
  raise "More team users than expected" if users.dig("links", "next")

  exact_matches = users.fetch("data").select { |user| user.dig("attributes", "username").casecmp?(email) }
  matching_gmail = users.fetch("data").count do |user|
    user.dig("attributes", "username").match?(/\Aa[^@]*@gmail\.com\z/i)
  end
  qq_users = exact_matches.map do |user|
    attributes = user.fetch("attributes")
    visible_apps = if attributes["allAppsVisible"]
      []
    else
      api.get("/v1/users/#{user.fetch("id")}/relationships/visibleApps").fetch("data")
    end
    attributes.slice("roles", "allAppsVisible", "provisioningAllowed").merge(
      "focus_visible" => attributes["allAppsVisible"] || visible_apps.any? { |app| app.fetch("id") == app_id },
      "focus_only" => visible_apps.map { |app| app.fetch("id") } == [app_id]
    )
  end
  puts JSON.generate(qq_team_users: qq_users, matching_gmail_team_user_count: matching_gmail)

  pending = api.get("/v1/userInvitations", "limit" => "200",
                    "fields[userInvitations]" => "email,expirationDate,roles,allAppsVisible")
  raise "More pending team invitations than expected" if pending.dig("links", "next")
  qq_pending = pending.fetch("data").select { |invite| invite.dig("attributes", "email").casecmp?(email) }
  puts JSON.generate(qq_team_invitations: qq_pending.map { |invite|
    invite.fetch("attributes").slice("expirationDate", "roles", "allAppsVisible")
  })
rescue StandardError => error
  abort "Team membership lookup failed (#{error.message[/HTTP [0-9]{3}/] || error.class})"
end

def restore_internal_membership(api, build_id)
  path = "/v1/betaGroups/#{GROUP_ID}/relationships/betaTesters"
  last_error = nil
  4.times do
    begin
      tester = target_tester_in_group(api, GROUP_ID)
      if tester && assigned?(api, build_id)
        return tester.dig("attributes", "state")
      end
      api.change_tester_membership(Net::HTTP::Post, path, TESTER_ID) unless tester
    rescue StandardError => error
      last_error = error.message
    end
    sleep 3
  end
  raise "Could not verify restored internal access: #{last_error || "Apple has not applied the membership"}"
end

def restore_by_account(api, app_id, build, group)
  email = confirmed_tester(api).fetch("email")
  tester_apps = api.get("/v1/betaTesters/#{TESTER_ID}/relationships/apps", "limit" => "200")
  tester_groups = api.get("/v1/betaTesters/#{TESTER_ID}/relationships/betaGroups", "limit" => "200")
  puts JSON.generate(account_tester_app_count: tester_apps.fetch("data").size,
                     focus_only: !tester_apps.dig("links", "next") &&
                       tester_apps.fetch("data").map { |app| app.fetch("id") } == [app_id],
                     account_tester_group_count: tester_groups.fetch("data").size,
                     internal_group_only: !tester_groups.dig("links", "next") &&
                       tester_groups.fetch("data").map { |entry| entry.fetch("id") } == [GROUP_ID])

  testers = api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
                    "fields[betaTesters]" => "state").fetch("data")
  linked_devices = testers.map do |tester|
    tester_id = tester.fetch("id")
    devices = read_diagnostics do
      detail = api.get("/v1/betaTesters/#{tester_id}", "fields[betaTesters]" => "appDevices")
      detail.dig("data", "attributes", "appDevices")&.map { |device| device.slice("platform", "appBuildVersion") }
    end
    { confirmed_recipient: tester.fetch("id") == TESTER_ID,
      state: tester.dig("attributes", "state"), devices: devices }
  end
  builds = api.builds(app_id)
  versions = builds.fetch("included", []).to_h { |entry| [entry.fetch("id"), entry.dig("attributes", "version")] }
  active = builds.fetch("data").reject { |entry| entry.dig("attributes", "expired") }
  puts JSON.generate(linked_devices: linked_devices, active_builds: active.map { |entry|
    [versions[entry.dig("relationships", "preReleaseVersion", "data", "id")], entry.dig("attributes", "version")]
  })

  build_id = build.fetch("id")
  raise "Expected automatic internal distribution" unless group[:internal_group] && group[:automatically_receives_builds]
  raise "Build 11 is not available to this group" unless assigned?(api, build_id)
  result_id = api.enroll_by_email(email, GROUP_ID)
  membership = api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
                       "fields[betaTesters]" => "email,state").fetch("data").find do |tester|
    tester.fetch("id") == result_id && tester.dig("attributes", "email").casecmp?(email)
  end
  raise "Apple did not confirm the internal tester membership" unless membership
  puts JSON.generate(qq_internal_enrollment_verified: true, reused_existing_tester: result_id == TESTER_ID,
                     state: membership.dig("attributes", "state"))
end

def audit_build_usage(api, app_id)
  testers = api.get("/v1/betaTesters", "filter[apps]" => app_id, "limit" => "200",
                    "fields[betaTesters]" => "state,appDevices")
  visible_testers = testers.fetch("data").map do |tester|
    attributes = tester.fetch("attributes")
    devices = attributes["appDevices"]&.map { |device| device.slice("platform", "appBuildVersion") }
    { confirmed_recipient: tester.fetch("id") == TESTER_ID, state: attributes["state"], devices: devices }
  end
  puts JSON.generate(app_tester_devices: visible_testers, more_testers: !!testers.dig("links", "next"))

  response = api.builds(app_id)
  versions = response.fetch("included", []).to_h { |entry| [entry.fetch("id"), entry.dig("attributes", "version")] }
  active = response.fetch("data").reject { |entry| entry.dig("attributes", "expired") }
  metrics = active.map do |build|
    attributes = build.fetch("attributes")
    build_id = build.fetch("id")
    usage = read_diagnostics do
      response = api.get("/v1/builds/#{build_id}/metrics/betaBuildUsages", "limit" => "200")
      points = response.fetch("data").flat_map { |row| row.fetch("dataPoints") }
      { installs: points.sum { |point| point.dig("values", "installCount").to_i },
        sessions: points.sum { |point| point.dig("values", "sessionCount").to_i },
        latest_metric_end: points.map { |point| point["end"] }.compact.max }
    end
    { version: versions[build.dig("relationships", "preReleaseVersion", "data", "id")],
      build: attributes.fetch("version"), uploaded: attributes.fetch("uploadedDate"), usage: usage }
  end
  puts JSON.generate(active_build_usage: metrics)
end

def rebuild_qq_tester(api, app_id, build, group)
  build_id = build.fetch("id")
  build_state = api.get("/v1/builds/#{build_id}/buildBetaDetail").dig("data", "attributes", "internalBuildState")
  unless build_state == "IN_BETA_TESTING" && group[:internal_group] &&
      group[:automatically_receives_builds] && assigned?(api, build_id)
    raise "Build 11 is unavailable for automatic internal distribution"
  end

  email = confirmed_tester(api).fetch("email")
  users = api.get("/v1/users", "filter[username]" => email, "fields[users]" => "username,roles").fetch("data")
  unless users.one? && users.first.dig("attributes", "username").casecmp?(email) &&
      users.first.dig("attributes", "roles").include?("ACCOUNT_HOLDER")
    raise "Apple did not confirm the original team account"
  end

  apps = api.get("/v1/betaTesters/#{TESTER_ID}/relationships/apps", "limit" => "200")
  groups = api.get("/v1/betaTesters/#{TESTER_ID}/relationships/betaGroups", "limit" => "200")
  unless !apps.dig("links", "next") && apps.fetch("data").map { |app| app.fetch("id") } == [app_id] &&
      !groups.dig("links", "next") && groups.fetch("data").map { |entry| entry.fetch("id") } == [GROUP_ID]
    raise "TestFlight record is associated with other apps or groups"
  end
  target = api.get("/v1/betaTesters", "filter[apps]" => app_id, "filter[id]" => TESTER_ID,
                   "fields[betaTesters]" => "state,appDevices").fetch("data")
  unless target.one? && target.first.fetch("id") == TESTER_ID &&
      target.first.dig("attributes", "state") == "INVITED" &&
      target.first.dig("attributes", "appDevices") == []
    raise "The TestFlight record has changed or has a linked device"
  end

  api.delete_tester(TESTER_ID)
  puts JSON.generate(qq_testflight_delete_accepted: true)

  begin
    deleted = false
    12.times do
      previous = api.get("/v1/betaTesters", "filter[id]" => TESTER_ID,
                         "fields[betaTesters]" => "state").fetch("data")
      if previous.empty?
        deleted = true
        break
      end
      sleep 4
    end
    raise "Apple retained the old TestFlight record after deletion" unless deleted

    result_id = api.enroll_by_email(email, GROUP_ID)
    membership = nil
    6.times do
      members = api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
                        "fields[betaTesters]" => "email,state").fetch("data")
      membership = members.find { |entry| entry.fetch("id") == result_id && entry.dig("attributes", "email").casecmp?(email) }
      break if membership
      sleep 3
    end
    raise "Apple did not confirm enrollment of the replacement tester" unless membership
    state = membership.dig("attributes", "state")
    api.resend_invitation(app_id, result_id) if state == "NOT_INVITED"
    puts JSON.generate(qq_testflight_record_rebuilt: true, new_tester_id: result_id != TESTER_ID,
                       state: state, build: BUILD_NUMBER)
  rescue StandardError => error
    puts JSON.generate(qq_testflight_rebuild_error: error.message.gsub(/[^\s]+@[^\s]+/, "[email]")[0, 400])
    state = restore_internal_membership(api, build_id)
    api.resend_invitation(app_id, TESTER_ID) if state == "NOT_INVITED"
    puts JSON.generate(qq_original_internal_membership_restored: true, state: state)
    exit 1
  end
end

def reset_tester_invitation(api, app_id, build_id)
  groups = api.get("/v1/apps/#{app_id}/betaGroups", "limit" => "200",
                   "fields[betaGroups]" => "isInternalGroup,hasAccessToAllBuilds").fetch("data")
  group_ids = groups.map { |group| group.fetch("id") }
  memberships = group_ids.select { |id| target_tester_in_group(api, id) }
  raise "Unexpected group memberships for the confirmed tester" unless memberships == [GROUP_ID]

  remove_path = "/v1/apps/#{app_id}/relationships/betaTesters"
  removal_confirmed = false
  begin
    status = api.change_tester_membership(Net::HTTP::Delete, remove_path, TESTER_ID)
    8.times do
      unless target_tester_in_group(api, GROUP_ID)
        removal_confirmed = true
        break
      end
      sleep 3
    end
    puts JSON.generate(removal_http_status: status, app_membership_removal_confirmed: removal_confirmed)
  ensure
    restored_state = restore_internal_membership(api, build_id)
    puts JSON.generate(internal_membership_restored: true, target_tester_state: restored_state,
                       build_number: BUILD_NUMBER, confirmed_recipient: "26***@qq.com")
  end
  raise "Apple did not confirm removal and reenrollment" unless removal_confirmed
  if restored_state == "NOT_INVITED"
    api.resend_invitation(app_id, TESTER_ID)
  end
end

$stdout.sync = true
api = FocusTestFlightClient.new(
  key_path: ENV.fetch("APP_STORE_CONNECT_KEY_PATH"),
  key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID")
)
app_id = api.app_id(TestFlightProcessing::BUNDLE_ID)
raise "Unexpected app" unless app_id == APP_ID
mode = ARGV.fetch(0)
group = group_status(api)
build = exact_build(api, app_id)
puts JSON.generate(app_id: app_id, exact_build: build&.fetch("attributes"), **group)

case mode
when "audit"
  audit_visibility(api, app_id, build)
  exit
when "audit-account"
  audit_team_account(api, app_id)
when "restore-by-account"
  raise "Build 11 is unavailable" unless build&.dig("attributes", "processingState") == "VALID" &&
    !build.dig("attributes", "expired")
  restore_by_account(api, app_id, build, group)
when "audit-build-usage"
  audit_build_usage(api, app_id)
when "rebuild-qq-tester"
  raise "Build 11 is unavailable" unless build&.dig("attributes", "processingState") == "VALID" &&
    !build.dig("attributes", "expired")
  rebuild_qq_tester(api, app_id, build, group)
when "reset-invitation", "restore-membership"
  raise "Build 11 is unavailable" unless build&.dig("attributes", "processingState") == "VALID" &&
    !build.dig("attributes", "expired") && assigned?(api, build.fetch("id"))
  raise "Expected internal automatic distribution" unless group[:internal_group] && group[:automatically_receives_builds]
  confirmed_tester(api)
  if mode == "reset-invitation"
    raise "Target is no longer in the expected group" unless group[:target_tester_state]
    reset_tester_invitation(api, app_id, build.fetch("id"))
  else
    state = restore_internal_membership(api, build.fetch("id"))
    puts JSON.generate(internal_membership_restored: true, target_tester_state: state, build_number: BUILD_NUMBER)
  end
when "reinvite", "assign-tester"
  raise "Build 11 is unavailable" unless build&.dig("attributes", "processingState") == "VALID" &&
    !build.dig("attributes", "expired") && assigned?(api, build.fetch("id"))
  raise "Internal membership changed" unless group[:internal_group] && group[:target_tester_state]
  tester = api.get("/v1/betaTesters/#{TESTER_ID}", "fields[betaTesters]" => "email,inviteType")
    .dig("data", "attributes")
  raise "Recipient does not match the confirmed account" unless masked_email(tester.fetch("email")) == "26***@qq.com"
  if mode == "reinvite"
    api.resend_invitation(app_id, TESTER_ID)
  else
    build_id = build.fetch("id")
    list_individuals = -> { api.get("/v1/builds/#{build_id}/individualTesters", "limit" => "200",
      "fields[betaTesters]" => "state").fetch("data") }
    assigned = ->(testers) { testers.any? { |entry| entry.fetch("id") == TESTER_ID } }
    api.assign_individual_tester(build_id, TESTER_ID) unless assigned.call(list_individuals.call)
    4.times do
      if assigned.call(list_individuals.call)
        puts JSON.generate(individual_assignment: "VERIFIED", recipient: "26***@qq.com", version: MARKETING_VERSION,
                           build: BUILD_NUMBER, internal_group_assignment: assigned?(api, build_id))
        exit
      end
      sleep 3
    end
    raise "Apple accepted the assignment but did not list it yet"
  end
when "preflight"
  raise "Build number is already registered; check its delivery run before any retry" if build
  raise "Target account is not in the expected internal group" unless group[:internal_group] && group[:target_tester_state]
  unless group[:automatically_receives_builds] || group[:tester_count] == 1
    raise "This group includes additional testers and requires a scoped distribution decision"
  end
when "verify"
  build_id = processed_build(api, app_id)
  if !assigned?(api, build_id) && !group[:automatically_receives_builds]
    raise "Tester membership changed" unless group[:internal_group] && group[:tester_count] == 1 && group[:target_tester_state]
    api.associate_build(GROUP_ID, build_id)
  end
  12.times do
    group = group_status(api)
    build_beta = api.get("/v1/builds/#{build_id}/buildBetaDetail").dig("data", "attributes")
    in_group = assigned?(api, build_id)
    if in_group && group[:internal_group] && group[:target_tester_state] && build_beta["internalBuildState"] == "IN_BETA_TESTING"
      puts JSON.generate(marketing_version: MARKETING_VERSION, build_number: BUILD_NUMBER, build_id: build_id,
                         processing_state: "VALID", internal_build_state: build_beta["internalBuildState"],
                         assigned_to_target_group: true, **group)
      exit
    end
    puts "Waiting for internal distribution: assigned=#{in_group}, status=#{build_beta["internalBuildState"]}"
    sleep 10
  end
  raise "Build processed, but TestFlight internal distribution was not confirmed"
else
  raise "Unknown action"
end
