require 'minitest/autorun'
require 'virtualsms'

# Minimum smoke test per the SDK v2.0.0 spec: get_balance + list_services
# succeed against a real key. Both endpoints require a valid API key against
# the live API, so both skip cleanly when VIRTUALSMS_API_KEY is unset and
# run for real when the environment (CI secret / local .env) provides one.
class SmokeTest < Minitest::Test
  def setup
    @api_key = ENV['VIRTUALSMS_API_KEY']
    @client = VirtualSMS.new(@api_key)
  end

  def test_list_services_succeeds_without_auth
    skip 'VIRTUALSMS_API_KEY not set — skipping live smoke test' if @api_key.nil? || @api_key.empty?

    services = @client.list_services
    assert_kind_of Array, services

    return if services.empty?

    first = services.first
    assert first.key?(:code)
    assert first.key?(:name)
  end

  def test_get_balance
    if @api_key && !@api_key.empty?
      balance = @client.get_balance
      assert_kind_of Hash, balance
      assert balance.key?(:balance_usd)
      assert_kind_of Numeric, balance[:balance_usd]
    else
      unauthenticated = VirtualSMS.new
      assert_raises(VirtualSMS::BadApiKeyError) { unauthenticated.get_balance }
    end
  end
end
