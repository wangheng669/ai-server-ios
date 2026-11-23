# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

module AppStoreConnect
  API_BASE = "https://api.appstoreconnect.apple.com"

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

    def post(path, payload)
      uri = URI.join(API_BASE, path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      perform(request)
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
      AppStoreConnect.jwt(
        key_path: @key_path,
        key_id: @key_id,
        issuer_id: @issuer_id
      )
    end
  end
end
