require 'net/http'
require 'uri'
require 'json'

# VirtualSMS Ruby SDK — SMS verification with real carrier SIMs.
#
# Unlike VoIP services, VirtualSMS uses real carrier-issued SIM cards across
# 145+ countries. 95%+ delivery rates on WhatsApp, Telegram, and platforms
# that block virtual numbers.
#
# Get your API key at https://virtualsms.io (Settings → API Keys)
# API Docs: https://virtualsms.io/api
# Pricing: https://virtualsms.io/pricing
#
# @example Quick start
#   client = VirtualSMS.new('vsms_your_api_key')
#   activation = client.get_number('wa', country: 22) # WhatsApp, UK
#   code = client.wait_for_code(activation[:activation_id])
#   puts "Code: #{code}"
#   client.done(activation[:activation_id])
class VirtualSMS
  BASE_URL = 'https://virtualsms.io/stubs/handler_api.php'

  class Error < StandardError; end
  class NoNumbersError < Error; end

  def initialize(api_key, base_url: BASE_URL)
    @api_key = api_key
    @base_url = base_url
  end

  # Get current account balance in USD.
  def get_balance
    result = request('getBalance')
    raise Error, result unless result.start_with?('ACCESS_BALANCE:')
    result.split(':')[1].to_f
  end

  # Request a phone number for SMS verification.
  # @param service [String] Service code ('wa', 'tg', 'go', etc.)
  # @param country [Integer] Country ID (187=US, 22=UK, 12=Germany)
  def get_number(service, country: 187)
    result = request('getNumber', service: service, country: country)
    if result.start_with?('ACCESS_NUMBER:')
      parts = result.split(':')
      { activation_id: parts[1].to_i, phone: parts[2], service: service, country: country }
    elsif result == 'NO_NUMBERS'
      raise NoNumbersError, "No numbers for #{service} in country #{country}"
    else
      raise Error, result
    end
  end

  # Check status of an activation.
  def get_status(activation_id)
    result = request('getStatus', id: activation_id)
    case result
    when 'STATUS_WAIT_CODE' then { status: 'waiting', code: nil }
    when /^STATUS_OK:/ then { status: 'received', code: result.split(':')[1] }
    when 'STATUS_CANCEL' then { status: 'cancelled', code: nil }
    else { status: result, code: nil }
    end
  end

  # Mark activation as done.
  def done(activation_id)
    request('setStatus', id: activation_id, status: 6)
  end

  # Cancel activation and get refund.
  def cancel(activation_id)
    request('setStatus', id: activation_id, status: 8)
  end

  # Wait for SMS code to arrive.
  # @param timeout [Integer] Max wait in seconds (default: 300)
  # @param poll_interval [Integer] Seconds between checks (default: 5)
  def wait_for_code(activation_id, timeout: 300, poll_interval: 5)
    start = Time.now
    while Time.now - start < timeout
      result = get_status(activation_id)
      return result[:code] if result[:code]
      return nil if result[:status] == 'cancelled'
      sleep(poll_interval)
    end
    nil
  end

  private

  def request(action, **params)
    uri = URI(@base_url)
    uri.query = URI.encode_www_form(params.merge(action: action, api_key: @api_key))
    Net::HTTP.get(uri).strip
  end
end
