#!/usr/bin/env ruby
# Rental flow: check availability, create a Full Access rental, extend it,
# and show how to cancel within the refund window.
#
#   VIRTUALSMS_API_KEY=vsms_... ruby examples/rental_flow.rb GB 24

require_relative '../lib/virtualsms'

api_key = ENV.fetch('VIRTUALSMS_API_KEY') { abort 'Set VIRTUALSMS_API_KEY first. Get one at https://virtualsms.io' }
country = ARGV[0] || 'GB'
duration_hours = (ARGV[1] || 24).to_i

client = VirtualSMS.new(api_key)

availability = client.rentals_available(country: country, tier: 'full_access')
puts "Available countries: #{availability[:total_available]}"

rental = client.create_rental(tier: 'full_access', country: country, duration_hours: duration_hours)
puts "Rental #{rental[:rental_id]}: #{rental[:phone_number]}, expires #{rental[:expires_at]}"

# Extend by another day if you need more time.
extended = client.extend_rental(rental_id: rental[:rental_id], duration_hours: 24)
puts "Extended: #{extended}"

# Full refund only within 20 minutes of purchase and before the first SMS.
# cancelled = client.cancel_rental(rental_id: rental[:rental_id])
# puts "Cancelled: #{cancelled}"

all = client.list_rentals(status: 'active')
puts "Active rentals: #{all.length}"
