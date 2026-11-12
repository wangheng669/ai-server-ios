# frozen_string_literal: true

require_relative "testflight-processing-notify"

APP_ID = "6793626100"
GROUP_ID = "e5f14909-f036-467c-aecb-4ea301c3dfd2"
TESTER_ID = "b219838f-16d1-466f-8d7f-b53b16f8b5da"
MARKETING_VERSION = "1.0.23"
BUILD_NUMBER = "13"

def exact_build(api, app_id, build_number: BUILD_NUMBER)
  response = api.builds(app_id)
  versions = response.fetch("included", []).to_h { |item| [item.fetch("id"), item.dig("attributes", "version")] }
  response.fetch("data").find do |item|
    item.dig("attributes", "version") == build_number &&
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

def automatically_distributed_to_target?(group)
  group[:internal_group] && group[:automatically_receives_builds] &&
    %w[ACCEPTED INSTALLED].include?(group[:target_tester_state])
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

$stdout.sync = true
api = TestFlightProcessing::Client.new(
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
  exit
when "preflight"
  raise "Build number is already registered; check its delivery run before any retry" if build
  raise "Target internal group cannot receive this build automatically" unless automatically_distributed_to_target?(group)
  previous = exact_build(api, app_id, build_number: "11")
  raise "Existing build 11 must remain available" unless previous&.dig("attributes", "expired") == false
when "verify"
  build_id = processed_build(api, app_id)
  audience = api.get("/v1/builds/#{build_id}", "fields[builds]" => "buildAudienceType").dig("data", "attributes", "buildAudienceType")
  raise "Expected an internal-only build" unless audience == "INTERNAL_ONLY"
  12.times do
    group = group_status(api)
    build_beta = api.get("/v1/builds/#{build_id}/buildBetaDetail").dig("data", "attributes")
    in_group = assigned?(api, build_id)
    if in_group && automatically_distributed_to_target?(group) && build_beta["internalBuildState"] == "IN_BETA_TESTING"
      puts JSON.generate(marketing_version: MARKETING_VERSION, build_number: BUILD_NUMBER, build_id: build_id,
                         processing_state: "VALID", internal_build_state: build_beta["internalBuildState"],
                         build_audience: audience, assigned_to_target_group: true, **group)
      exit
    end
    puts "Waiting for internal distribution: assigned=#{in_group}, status=#{build_beta["internalBuildState"]}"
    sleep 10
  end
  raise "Build processed, but TestFlight internal distribution was not confirmed"
else
  raise "Unknown action"
end
