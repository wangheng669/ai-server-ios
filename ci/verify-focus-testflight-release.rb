# frozen_string_literal: true

require_relative "testflight-processing-notify"

APP_ID = "6793626100"
GROUP_ID = "e5f14909-f036-467c-aecb-4ea301c3dfd2"
TESTER_ID = "b219838f-16d1-466f-8d7f-b53b16f8b5da"
MARKETING_VERSION = "1.0.23"
BUILD_NUMBER = "11"

class FocusTestFlightClient < TestFlightProcessing::Client
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
when "reinvite"
  raise "Build 11 is unavailable" unless build&.dig("attributes", "processingState") == "VALID" &&
    !build.dig("attributes", "expired") && assigned?(api, build.fetch("id"))
  raise "Internal membership changed" unless group[:internal_group] && group[:target_tester_state]
  tester = api.get("/v1/betaTesters/#{TESTER_ID}", "fields[betaTesters]" => "email,inviteType")
    .dig("data", "attributes")
  raise "Recipient does not match the confirmed account" unless masked_email(tester.fetch("email")) == "26***@qq.com"
  api.resend_invitation(app_id, TESTER_ID)
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
