#!/usr/bin/env ruby
# Basic SMS verification flow: buy a number, wait for the code, cancel if
# it never arrives.
#
#   VIRTUALSMS_API_KEY=vsms_... ruby examples/activation_flow.rb wa GB

require_relative '../lib/virtualsms'

api_key = ENV.fetch('VIRTUALSMS_API_KEY') { abort 'Set VIRTUALSMS_API_KEY first. Get one at https://virtualsms.io' }
service = ARGV[0] || 'wa'
country = ARGV[1] || 'GB'

client = VirtualSMS.new(api_key)

price = client.get_price(service: service, country: country)
unless price[:available]
  warn "#{service}/#{country} not in stock: #{price[:message]}"
  cheapest = client.find_cheapest(service: service)
  warn "Try one of: #{cheapest[:cheapest_options].map { |o| o[:country] }.join(', ')}" unless cheapest[:cheapest_options].empty?
  exit 1
end

puts "Price: $#{price[:price_usd]} #{price[:currency]}"

order = client.create_order(service: service, country: country)
puts "Number: #{order[:phone_number]} (order #{order[:order_id]})"

puts 'Waiting for SMS (up to 5 minutes)...'
result = client.wait_for_sms(order_id: order[:order_id])

if result[:success]
  puts "Code: #{result[:code]}"
else
  puts 'No SMS yet, cancelling for a refund.'
  cancel = client.cancel_order(order_id: order[:order_id])
  puts cancel
end
