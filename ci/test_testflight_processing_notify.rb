# frozen_string_literal: true

require "json"
require "openssl"
require "tempfile"
require "minitest/autorun"
require_relative "testflight-processing-notify"

class TestFlightProcessingNotifyTest < Minitest::Test
  def test_generates_es256_jwt_with_raw_signature
    key = OpenSSL::PKey::EC.generate("prime256v1")
    Tempfile.create("app-store-key") do |file|
      file.write(key.to_pem)
      file.flush
      token = TestFlightProcessing.jwt(
        key_path: file.path,
        key_id: "KEY123",
        issuer_id: "issuer",
        now: 1_700_000_000
      )
      header, payload, signature = token.split(".").map { |part| Base64.urlsafe_decode64(part) }
      assert_equal "KEY123", JSON.parse(header).fetch("kid")
      assert_equal "issuer", JSON.parse(payload).fetch("iss")
      assert_equal 64, signature.bytesize
    end
  end

  def test_selects_new_build_and_resolves_marketing_version
    response = {
      "data" => [
        {
          "id" => "new",
          "attributes" => {
            "version" => "9",
            "uploadedDate" => "2026-07-28T09:40:00Z",
            "processingState" => "VALID"
          },
          "relationships" => {
            "preReleaseVersion" => { "data" => { "id" => "version-id" } }
          }
        },
        { "id" => "old", "attributes" => {} }
      ],
      "included" => [
        { "id" => "version-id", "attributes" => { "version" => "1.0" } }
      ]
    }

    details = TestFlightProcessing.build_details(response, ["old"])
    assert_equal "1.0", details.fetch("version")
    assert_equal "9", details.fetch("build")
    assert_equal "VALID", details.fetch("state")
  end
end
