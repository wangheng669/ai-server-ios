# frozen_string_literal: true

require_relative "testflight-processing-notify"

APP_ID = "6793626100"
GROUP_ID = "2476542b-3a15-4536-92ac-fbf8fceb69c0"
VERSION = "1.0.23"
BUILD = "12"
REVIEW_STATES = %w[WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW READY_FOR_BETA_TESTING IN_BETA_TESTING].freeze
TEST_NOTES = "验证 iPhone 上首次安装与自动更新，检查首页、资讯列表及通知详情。".freeze

class ExternalTestFlightClient < TestFlightProcessing::Client
  def create(path, payload, expected_code)
    uri = URI.join(TestFlightProcessing::API_BASE, path)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    return if response.code == expected_code

    result = JSON.parse(response.body) rescue {}
    errors = Array(result["errors"]).map do |error|
      [error["code"], error["detail"].to_s.gsub(/[^\s]+@[^\s]+/, "[email]")[0, 220]]
    end
    raise "App Store Connect #{path} returned HTTP #{response.code}: #{JSON.generate(errors)}"
  end
end

def linkage(type, id)
  { type: type, id: id }
end

def build_info(api, app_id)
  response = api.builds(app_id)
  versions = response.fetch("included", []).to_h { |item| [item.fetch("id"), item.dig("attributes", "version")] }
  response.fetch("data").find do |item|
    item.dig("attributes", "version") == BUILD &&
      versions[item.dig("relationships", "preReleaseVersion", "data", "id")] == VERSION
  end
end

def external_group(api)
  api.get("/v1/betaGroups/#{GROUP_ID}",
          "fields[betaGroups]" => "name,isInternalGroup,publicLinkEnabled,publicLinkLimitEnabled,publicLinkLimit,publicLink")
    .dig("data", "attributes")
end

def group_build_ids(api)
  api.get("/v1/betaGroups/#{GROUP_ID}/builds", "limit" => "200",
          "fields[builds]" => "version").fetch("data").map { |item| item.fetch("id") }
end

def group_tester_count(api)
  api.get("/v1/betaGroups/#{GROUP_ID}/betaTesters", "limit" => "200",
          "fields[betaTesters]" => "state").fetch("data").size
end

def beta_details(api, build_id)
  api.get("/v1/builds/#{build_id}/buildBetaDetail").fetch("data")
end

def review_metadata(api, app_id)
  localizations = api.get("/v1/apps/#{app_id}/betaAppLocalizations", "limit" => "50",
                          "fields[betaAppLocalizations]" => "locale,description,feedbackEmail").fetch("data")
  details = api.get("/v1/betaAppReviewDetails", "filter[app]" => app_id,
                    "fields[betaAppReviewDetails]" =>
                      "contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes")
    .fetch("data").first
  fields = details ? details.fetch("attributes") : {}
  {
    localizations: localizations.map do |item|
      attributes = item.fetch("attributes")
      { locale: attributes["locale"], has_description: !attributes["description"].to_s.strip.empty?,
        has_feedback_email: !attributes["feedbackEmail"].to_s.strip.empty? }
    end,
    review_contact: %w[contactFirstName contactLastName contactPhone contactEmail].to_h do |field|
      [field, !fields[field].to_s.strip.empty?]
    end,
    demo_account_required: fields["demoAccountRequired"],
    has_review_notes: !fields["notes"].to_s.strip.empty?
  }
end

def valid_build(api, app_id)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 900
  loop do
    build = build_info(api, app_id)
    state = build&.dig("attributes", "processingState")
    raise "Apple rejected the upload (#{state})" if %w[FAILED INVALID].include?(state)
    if state == "VALID"
      raise "Build has expired" if build.dig("attributes", "expired")
      id = build.fetch("id")
      audience = api.get("/v1/builds/#{id}", "fields[builds]" => "buildAudienceType").dig("data", "attributes", "buildAudienceType")
      raise "The build cannot be used in an external group" unless audience == "APP_STORE_ELIGIBLE"
      return id
    end
    puts "Waiting for Apple processing: #{state || "not yet listed"}"
    raise "Timed out waiting for Apple processing" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 15
  end
end

def prepare_review_notes(api, build_id)
  notes = api.get("/v1/builds/#{build_id}/betaBuildLocalizations", "limit" => "50",
                  "fields[betaBuildLocalizations]" => "locale,whatsNew").fetch("data")
  localized = notes.find { |item| item.dig("attributes", "locale") == "zh-Hans" }
  if localized
    return unless localized.dig("attributes", "whatsNew").to_s.strip.empty?

    id = localized.fetch("id")
    api.patch("/v1/betaBuildLocalizations/#{id}", data: {
      type: "betaBuildLocalizations", id: id, attributes: { whatsNew: TEST_NOTES }
    })
  else
    api.create("/v1/betaBuildLocalizations", { data: {
      type: "betaBuildLocalizations", attributes: { locale: "zh-Hans", whatsNew: TEST_NOTES },
      relationships: { build: { data: linkage("builds", build_id) } }
    } }, "201")
  end
end

def start_review(api, app_id, group)
  raise "Expected the external group with invitations closed" unless !group.fetch("isInternalGroup") && !group["publicLinkEnabled"]
  raise "The external group has other testers" unless group_tester_count(api).zero?
  id = valid_build(api, app_id)
  details = beta_details(api, id)
  state = details.dig("attributes", "externalBuildState")
  raise "Apple marked the build as #{state}" if %w[REJECTED BETA_REJECTED EXPIRED NOT_APPLICABLE].include?(state)
  group_ids = group_build_ids(api)
  raise "The external group already contains another build" unless (group_ids - [id]).empty?
  unless group_ids.include?(id)
    prepare_review_notes(api, id)
    api.create("/v1/betaGroups/#{GROUP_ID}/relationships/builds", { data: [linkage("builds", id)] }, "204")
  end
  state = beta_details(api, id).dig("attributes", "externalBuildState")
  unless REVIEW_STATES.include?(state)
    api.create("/v1/betaAppReviewSubmissions", { data: {
      type: "betaAppReviewSubmissions",
      relationships: { build: { data: linkage("builds", id) } }
    } }, "201")
  end
  8.times do
    state = beta_details(api, id).dig("attributes", "externalBuildState")
    if REVIEW_STATES.include?(state) && group_build_ids(api).include?(id)
      puts JSON.generate(review_build: VERSION, build: BUILD, external_build_state: state,
                         assigned_to_external_group: true, invitations_open: false)
      return
    end
    sleep 5
  end
  raise "Apple has not confirmed the external review state (#{state})"
end

def write_invitation(api, app_id, group)
  id = valid_build(api, app_id)
  state = beta_details(api, id).dig("attributes", "externalBuildState")
  unless %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].include?(state)
    raise "Apple has not approved the external build (#{state})"
  end
  archive = ENV.fetch("ARCHIVE_PATH")
  expected_path = %r{\A/Users/wang/\.cache/ai-server-ios/testflight-1\.0\.23-build12\.[A-Za-z0-9]+/VerifiedAIServerClient\.xcarchive\.zip\z}
  raise "Expected the local release archive" unless archive.match?(expected_path) && File.file?(archive) && !File.symlink?(archive)
  raise "Expected only build 12 in the external group" unless group_build_ids(api) == [id] && !group.fetch("isInternalGroup")
  unless group["publicLinkEnabled"]
    raise "External group already has a tester" unless group_tester_count(api).zero?
    api.patch("/v1/betaGroups/#{GROUP_ID}", data: {
      type: "betaGroups", id: GROUP_ID,
      attributes: { publicLinkEnabled: true, publicLinkLimitEnabled: true, publicLinkLimit: 1 }
    })
  end
  updated = external_group(api)
  url = updated["publicLink"].to_s
  unless updated["publicLinkEnabled"] && updated["publicLinkLimitEnabled"] && updated["publicLinkLimit"] == 1 &&
      url.match?(%r{\Ahttps://testflight\.apple\.com/join/[A-Za-z0-9]+\z})
    raise "Apple has not confirmed the one-tester invitation"
  end
  File.open(File.join(File.dirname(archive), "private-testflight-invite.json"), "w", 0o600) do |file|
    file.write(JSON.generate(url: url, tester_limit: 1, version: VERSION, build: BUILD))
  end
  puts JSON.generate(private_invitation_saved: true, tester_limit: 1, build: BUILD)
end

$stdout.sync = true
api = ExternalTestFlightClient.new(
  key_path: ENV.fetch("APP_STORE_CONNECT_KEY_PATH"),
  key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID")
)
app_id = api.app_id(TestFlightProcessing::BUNDLE_ID)
raise "Unexpected app" unless app_id == APP_ID
group = external_group(api)
mode = ARGV.fetch(0)
case mode
when "audit"
  build = build_info(api, app_id)
  state = build ? beta_details(api, build.fetch("id")).dig("attributes", "externalBuildState") : nil
  puts JSON.generate(external_group: group.fetch("name"), invitations_open: group["publicLinkEnabled"],
                     tester_count: group_tester_count(api), group_build_count: group_build_ids(api).size,
                     build_registered: !build.nil?, external_build_state: state, **review_metadata(api, app_id))
when "preflight"
  raise "Build 12 is already registered; use the review operation" if build_info(api, app_id)
  raise "Unexpected external group" if group.fetch("isInternalGroup") || group["publicLinkEnabled"]
when "review"
  start_review(api, app_id, group)
when "issue-link"
  write_invitation(api, app_id, group)
else
  raise "Unknown action"
end
