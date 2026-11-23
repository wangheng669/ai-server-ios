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
  abort "Apple Developer returned a different device." unless attributes.fetch("udid").casecmp?(udid)

  device_id = device.fetch("id")
  device_path = "/v1/devices/#{device_id}"
  status = attributes.fetch("status")
  if status == "DISABLED"
    response = client.patch(device_path, data: { type: "devices", id: device_id, attributes: { status: "ENABLED" } })
    status = response.fetch("data").fetch("attributes").fetch("status")
  end
  10.times do
    break unless status == "PROCESSING"

    sleep 6
    status = client.get(device_path).fetch("data").fetch("attributes").fetch("status")
  end
  abort "Apple Developer status for Focus device ending in #{udid[-8, 8]}: #{status} (requires ENABLED)." unless status == "ENABLED"
end

puts "Apple Developer has #{udids.length} enabled devices for Focus."
