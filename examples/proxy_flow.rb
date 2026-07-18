#!/usr/bin/env ruby
# Proxy flow: browse the catalog, buy traffic, generate a connection string,
# test the exit IP, and rotate.
#
#   VIRTUALSMS_API_KEY=vsms_... ruby examples/proxy_flow.rb residential GB 1

require_relative '../lib/virtualsms'

api_key = ENV.fetch('VIRTUALSMS_API_KEY') { abort 'Set VIRTUALSMS_API_KEY first. Get one at https://virtualsms.io' }
pool_type = ARGV[0] || 'residential'
country_code = ARGV[1] || 'GB'
gb = (ARGV[2] || 1).to_f

client = VirtualSMS.new(api_key)

catalog = client.list_proxy_catalog
pool = catalog.find { |p| p[:id] == pool_type }
puts "#{pool_type}: $#{pool[:price_per_gb]}/GB" if pool

purchase = client.buy_proxy(pool_type: pool_type, gb: gb, country_code: country_code)
puts "Bought proxy #{purchase[:proxy_id]}: #{purchase[:gb_added]}GB"

endpoint = client.generate_proxy_endpoint(
  proxy_id: purchase[:proxy_id],
  country_code: country_code,
  format: 'curl'
)
puts "Connection: #{endpoint[:endpoints].first}"

test = client.test_proxy(proxy_id: purchase[:proxy_id], country: country_code)
puts "Exit IP: #{test[:exit_ip]} (#{test[:city]}, #{test[:country_name]})"

rotated = client.rotate_proxy(proxy_id: purchase[:proxy_id])
puts "Rotated: #{rotated}"
