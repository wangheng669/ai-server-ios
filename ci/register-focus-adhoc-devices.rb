# frozen_string_literal: true

require_relative "app-store-connect"

key_path, key_id, issuer_id = ARGV
client = AppStoreConnect::Client.new(key_path: key_path, key_id: key_id, issuer_id: issuer_id)
udids = JSON.parse($stdin.read)

udids.each do |udid|
  devices = client.get("/v1/devices", "filter[udid]" => udid).fetch("data")
  device = devices.find { |record| record.fetch("attributes").fetch("udid").casecmp?(udid) }
  unless device
    device = client.post(
      "/v1/devices",
      data: {
        type: "devices",
        attributes: { name: "Focus #{udid[-8, 8]}", platform: "IOS", udid: udid }
      }
    ).fetch("data")
  end
  attributes = device.fetch("attributes")
  unless attributes.fetch("udid").casecmp?(udid) && attributes.fetch("status") == "ENABLED"
    abort "Focus device ending in #{udid[-8, 8]} is not enabled in Apple Developer."
  end
end

puts "Apple Developer has #{udids.length} enabled devices for Focus."
