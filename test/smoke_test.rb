require 'minitest/autorun'
require 'virtualsms'

# Minimum smoke test per the SDK v2.0.0 spec: get_balance + list_services
# succeed against a real key or a throwaway one. list_services is a public
# endpoint (no key required, no cost, safe to call from CI on every run).
# get_balance requires an API key: if VIRTUALSMS_API_KEY is set in the
# environment (CI secret / local .env), it's exercised against the live
# endpoint; otherwise this test asserts the client-side guard fires
# (BadApiKeyError, no network call made) so the suite still passes in CI
# without a secret configured.
class SmokeTest < Minitest::Test
  def setup
    @api_key = ENV['VIRTUALSMS_API_KEY']
    @client = VirtualSMS.new(@api_key)
  end

  def test_list_services_succeeds_without_auth
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
