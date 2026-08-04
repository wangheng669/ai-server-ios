#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

module TestFlightProcessing
  API_BASE = "https://api.appstoreconnect.apple.com"
  BUNDLE_ID = "com.wangheng.aiserverclient"

  module_function

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def jwt(key_path:, key_id:, issuer_id:, now: Time.now.to_i)
    header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
    payload = base64url(JSON.generate(
      iss: issuer_id,
      iat: now - 5,
      exp: now + 600,
      aud: "appstoreconnect-v1"
    ))
    signing_input = "#{header}.#{payload}"
    key = OpenSSL::PKey.read(File.read(key_path))
    der_signature = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
    sequence = OpenSSL::ASN1.decode(der_signature)
    signature = sequence.value.map do |integer|
      [integer.value.to_i.to_s(16).rjust(64, "0")].pack("H*")
    end.join
    "#{signing_input}.#{base64url(signature)}"
  end

  class Client
    def initialize(key_path:, key_id:, issuer_id:)
      @key_path = key_path
      @key_id = key_id
      @issuer_id = issuer_id
    end

    def get(path, params = {})
      uri = URI.join(API_BASE, path)
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri)
      perform(request)
    end

    def patch(path, payload)
      uri = URI.join(API_BASE, path)
      request = Net::HTTP::Patch.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      perform(request)
    end

    def expire_build(build_id)
      patch(
        "/v1/builds/#{build_id}",
        data: {
          type: "builds",
          id: build_id,
          attributes: { expired: true }
        }
      )
    end

    def app_id(bundle_id)
      response = get("/v1/apps", "filter[bundleId]" => bundle_id, "limit" => "1")
      response.fetch("data").first&.fetch("id") || raise("App not found for bundle ID #{bundle_id}")
    end

    def builds(app_id, limit: 200)
      get(
        "/v1/builds",
        "filter[app]" => app_id,
        "sort" => "-uploadedDate",
        "limit" => limit.to_s,
        "include" => "preReleaseVersion",
        "fields[builds]" => "version,uploadedDate,processingState,expired,preReleaseVersion",
        "fields[preReleaseVersions]" => "version"
      )
    end

    private

    def perform(request)
      request["Authorization"] = "Bearer #{token}"
      uri = request.uri
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        open_timeout: 10,
        read_timeout: 30
      ) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise "App Store Connect API returned HTTP #{response.code}: #{response.body}"
      end

      JSON.parse(response.body)
    end

    def token
      TestFlightProcessing.jwt(
        key_path: @key_path,
        key_id: @key_id,
        issuer_id: @issuer_id
      )
    end
  end

  def build_details(response, baseline_ids)
    versions = response.fetch("included", []).to_h do |item|
      [item.fetch("id"), item.dig("attributes", "version")]
    end
    build = response.fetch("data").find { |item| !baseline_ids.include?(item.fetch("id")) }
    return nil unless build

    prerelease_id = build.dig("relationships", "preReleaseVersion", "data", "id")
    {
      "id" => build.fetch("id"),
      "version" => versions[prerelease_id] || "unknown",
      "build" => build.dig("attributes", "version") || "unknown",
      "uploadedAt" => build.dig("attributes", "uploadedDate"),
      "state" => build.dig("attributes", "processingState")
    }
  end

  def marketing_versions(response)
    response.fetch("included", []).map do |item|
      next unless item["type"] == "preReleaseVersions"

      item.dig("attributes", "version")
    end.compact.uniq
  end

  def version_components(value)
    return nil unless value.to_s.match?(/\A\d+(?:\.\d+){0,2}\z/)

    value.split(".").map(&:to_i).then { |parts| parts + Array.new(3 - parts.length, 0) }
  end

  def next_marketing_version(response, base_version: "1.0")
    candidates = (marketing_versions(response) + [base_version]).map do |version|
      components = version_components(version)
      [components, version] if components
    end.compact
    raise "No valid marketing version is available" if candidates.empty?

    major, minor, patch = candidates.max_by(&:first).first
    [major, minor, patch + 1].join(".")
  end

  def append_github_env(name, value)
    path = required_env("GITHUB_ENV")
    File.open(path, "a") { |file| file.puts("#{name}=#{value}") }
  end

  def active_build_ids(response)
    response.fetch("data").map do |item|
      attributes = item.fetch("attributes", {})
      next if attributes["expired"]
      next unless attributes["processingState"] == "VALID"

      item.fetch("id")
    end.compact
  end

  def expire_builds(api, build_ids)
    build_ids.each do |build_id|
      attempts = 0
      begin
        attempts += 1
        api.expire_build(build_id)
      rescue StandardError
        raise if attempts >= 3

        sleep 5
        retry
      end
    end
    build_ids.length
  end

  def notify_server(status:, details:, error: nil)
    base_url = ENV.fetch("DEPLOYMENT_STATUS_BASE_URL", "https://api.wanghengai.xin")
    api_key = required_env("DEPLOYMENT_STATUS_API_KEY")
    uri = URI.join("#{base_url.sub(%r{/*$}, "")}/", "api/ios/v1/system/ios-testflight-notification")
    payload = {
      status: status,
      version: details.fetch("version", "unknown"),
      build: details.fetch("build", "unknown"),
      commit: ENV["GITHUB_SHA"],
      runUrl: github_run_url,
      uploadedAt: details["uploadedAt"],
      completedAt: Time.now.utc.iso8601,
      error: error
    }.compact

    last_error = nil
    3.times do |attempt|
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-API-Key"] = api_key
      request.body = JSON.generate(payload)
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 20
      ) { |http| http.request(request) }
      return if response.is_a?(Net::HTTPSuccess)

      last_error = "AI Server returned HTTP #{response.code}: #{response.body}"
      sleep 5 if attempt < 2
    rescue StandardError => e
      last_error = e.message
      sleep 5 if attempt < 2
    end
    raise "DingTalk notification failed after 3 attempts: #{last_error}"
  end

  def github_run_url
    values = %w[GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_RUN_ID].map { |name| ENV[name].to_s.strip }
    return nil if values.any?(&:empty?)

    "#{values[0]}/#{values[1]}/actions/runs/#{values[2]}"
  end

  def mark_notified
    return if ENV["GITHUB_ENV"].to_s.empty?

    File.open(ENV["GITHUB_ENV"], "a") { |file| file.puts("TESTFLIGHT_TERMINAL_NOTIFIED=true") }
  end

  def required_env(name)
    value = ENV[name].to_s.strip
    raise "#{name} is required" if value.empty?

    value
  end

  def client
    Client.new(
      key_path: required_env("APP_STORE_CONNECT_KEY_PATH"),
      key_id: required_env("APP_STORE_CONNECT_KEY_ID"),
      issuer_id: required_env("APP_STORE_CONNECT_ISSUER_ID")
    )
  end

  def snapshot(path)
    api = client
    app_id = api.app_id(BUNDLE_ID)
    response = api.builds(app_id)
    ids = response.fetch("data").map { |item| item.fetch("id") }
    File.write(
      path,
      JSON.pretty_generate(
        appId: app_id,
        buildIds: ids,
        activeBuildIds: active_build_ids(response)
      )
    )
    puts "Captured #{ids.length} existing TestFlight build IDs."
  end

  def prepare(path)
    api = client
    app_id = api.app_id(BUNDLE_ID)
    response = api.builds(app_id)
    ids = response.fetch("data").map { |item| item.fetch("id") }
    version = next_marketing_version(
      response,
      base_version: ENV.fetch("TESTFLIGHT_BASE_MARKETING_VERSION", "1.0")
    )
    File.write(
      path,
      JSON.pretty_generate(
        appId: app_id,
        buildIds: ids,
        activeBuildIds: active_build_ids(response),
        marketingVersion: version
      )
    )
    append_github_env("TESTFLIGHT_MARKETING_VERSION", version)
    puts "Next TestFlight marketing version: #{version}"
    puts "Captured #{ids.length} existing TestFlight build IDs."
  end

  def wait(path)
    baseline = JSON.parse(File.read(path))
    baseline_ids = baseline.fetch("buildIds")
    timeout_seconds = Integer(ENV.fetch("TESTFLIGHT_PROCESSING_TIMEOUT_SECONDS", "1800"))
    poll_seconds = Integer(ENV.fetch("TESTFLIGHT_PROCESSING_POLL_SECONDS", "30"))
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    api = client
    latest_details = { "version" => "unknown", "build" => "unknown" }

    loop do
      details = fetch_new_build(api, baseline.fetch("appId"), baseline_ids)
      if details
        latest_details = details
        state = details["state"]
        puts "Build #{details["version"]} (#{details["build"]}) processing state: #{state}"
        if state == "VALID"
          old_build_ids = baseline.fetch("activeBuildIds", baseline_ids)
          expired_count = expire_builds(api, old_build_ids)
          puts "Expired #{expired_count} previous TestFlight builds."
          notify_server(status: "completed", details: details)
          mark_notified
          puts "TestFlight processing completed and DingTalk notification was sent."
          return
        end
        if %w[FAILED INVALID].include?(state)
          notify_server(status: "failed", details: details, error: "App Store Connect processing state: #{state}")
          mark_notified
          raise "TestFlight processing failed with state #{state}"
        end
      else
        puts "Waiting for the uploaded build to appear in App Store Connect..."
      end

      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep poll_seconds
    end

    notify_server(status: "failed", details: latest_details, error: "Timed out waiting for App Store Connect processing")
    mark_notified
    raise "Timed out after #{timeout_seconds} seconds waiting for TestFlight processing"
  end

  def fetch_new_build(api, app_id, baseline_ids)
    api.builds(app_id).then { |response| build_details(response, baseline_ids) }
  rescue StandardError => e
    warn "Temporary polling error: #{e.message}"
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  command, path = ARGV
  commands = %w[prepare snapshot wait]
  abort "Usage: #{$PROGRAM_NAME} prepare|snapshot|wait SNAPSHOT_PATH" unless commands.include?(command) && path

  TestFlightProcessing.public_send(command, path)
end
