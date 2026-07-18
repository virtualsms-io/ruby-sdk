# VirtualSMS Ruby SDK

VirtualSMS is an account verification platform for individuals, developers and AI agents. It combines one-time SMS verification, dedicated number rentals, matching-country proxies and private cloud browser sessions behind one API, one MCP server and one prepaid balance.

Built for developers and AI agents: REST API, hosted MCP server, SDKs.

This gem is a **native Ruby client for the VirtualSMS REST API v1** (`/api/v1/*`), covering the full public surface: services, countries, pricing, orders, rentals (Full Access and Platform tier), proxies, account, browser sessions and webhooks. It is not a wrapper around any third-party protocol.

## Installation

```bash
gem install virtualsms-sdk
```

Or add to your Gemfile:

```ruby
gem 'virtualsms-sdk'
```

## Quick Start

```ruby
require 'virtualsms'

# Get your API key at https://virtualsms.io/dashboard (Settings, API Keys)
client = VirtualSMS.new(ENV.fetch('VIRTUALSMS_API_KEY'))

# 1. Buy a number for WhatsApp verification in the UK
order = client.create_order(service: 'wa', country: 'GB')
puts "Use this number: #{order[:phone_number]}"

# 2. Wait for the verification code (blocks, polls every 5s, 5 minute default timeout)
result = client.wait_for_sms(order_id: order[:order_id])
if result[:success]
  puts "Code: #{result[:code]}"
else
  puts "No code yet. Retry client.get_sms(order_id: order[:order_id]) later."
end
```

## Services and countries

Service and country codes are not hardcoded in this SDK. Look them up live:

```ruby
services = client.list_services   # [{code:, name:, icon:}, ...]
countries = client.list_countries # [{iso:, name:, flag:}, ...]

# Fuzzy match by name instead of memorizing codes
client.search_services(query: 'binance') # => matches with match_score

# Cheapest in-stock countries for a service
client.find_cheapest(service: 'wa', limit: 5)
```

2500+ services, 145+ countries. Full lists at [virtualsms.io/services](https://virtualsms.io/services) and [virtualsms.io/pricing](https://virtualsms.io/pricing).

## API reference

`VirtualSMS.new(api_key = nil, base_url: 'https://virtualsms.io/api/v1', timeout: 30)`

`api_key` is optional for public endpoints (catalog, pricing, public lookups); any authenticated method raises `VirtualSMS::BadApiKeyError` without one. `base_url` can also be set via the `VIRTUALSMS_BASE_URL` environment variable.

### Activations / orders

| Method | Purpose |
|---|---|
| `list_services` | List all SMS-verification services. Public. |
| `list_countries` | List all available countries. Public. |
| `get_price(service:, country:)` | Price + real stock for a service+country combo. Public. |
| `create_order(service:, country:)` | Buy a number for one-off verification. |
| `get_order(order_id:)` | Full order detail, including any received SMS. |
| `get_sms(order_id:)` | Poll for SMS delivery (normalizes the message shape, extracts the numeric code). |
| `wait_for_sms(order_id:, timeout_seconds: 300, interval_seconds: 5)` | Block until an SMS arrives or timeout. Never raises on timeout. |
| `cancel_order(order_id:)` | Cancel and refund (before any SMS received). |
| `swap_number(order_id:)` | Get a new number for the same service/country, no extra charge. |
| `retry_order(order_id:)` | Ask for the SMS to be resent to the same number. |
| `list_orders(status: nil)` | List orders, optional status filter. |
| `order_history(status:, service:, country:, since_days:, limit: 20)` | Filtered order history, capped at 50 rows. |
| `cancel_all_orders` | Bulk-cancel every active order. |
| `search_services(query:)` | Fuzzy-match a service by name ("uber", "steam", "binance"). |
| `find_cheapest(service:, limit: 5)` | Cheapest in-stock countries for a service, sorted by price. |

### Rentals

Two tiers, both refund-identical (full refund within 20 minutes of purchase, before the first SMS): `full_access` (local SIM inventory, any service) and `platform` (global supplier network, one service per number, 24/72/168h durations only).

| Method | Purpose |
|---|---|
| `rentals_pricing` | Raw Full Access pricing tiers. Public. |
| `rentals_available(country:, service:, type:, tier:)` | Country availability + pricing per tier. Public. |
| `rentals_services(country_code:, duration_hours: 24)` | Platform-tier services available in a country, with stock and price. Public. |
| `rentals_price(service:, country_code:, duration_hours:)` | Catalog price for a platform-tier combo. Public. |
| `create_rental(tier:, country:, duration_hours:, service:, auto_renew:)` | Create a rental in either tier. |
| `list_rentals(status: nil)` | List rentals, optional status filter. |
| `get_rental(rental_id:)` | Get one rental by id. |
| `extend_rental(rental_id:, duration_hours:)` | Extend an active rental at the current catalog price. |
| `cancel_rental(rental_id:)` | Full refund within the 20 minute window. |

### Proxies

| Method | Purpose |
|---|---|
| `list_proxy_catalog` | Pool types, countries, price per GB. Public. |
| `list_proxies` | Owned proxies with credentials. |
| `buy_proxy(pool_type:, gb:, country_code:, idempotency_key:)` | Purchase proxy traffic. |
| `rotate_proxy(proxy_id:, port:)` | Get a fresh exit IP. |
| `get_proxy_usage(proxy_id:)` | Cached GB used/remaining. |
| `get_proxy_usage_history(proxy_id:, range: '7d')` | Per-day GB/requests series, `7d` or `30d`. |
| `set_proxy_targeting(proxy_id:, country_code:, cities:, asns:)` | Persist default geo-targeting. |
| `test_proxy(proxy_id:, country:, session:, protocol:)` | Dial out and report exit IP/country/latency. |
| `list_proxy_locations(pool_type:, country:, kind:)` | Valid cities/states/asns/zips for a pool type. Public. |
| `generate_proxy_endpoint(proxy_id:, country_code:, ...)` | Compose a ready-to-use connection string. Pure function, no purchase. |

### Account

| Method | Purpose |
|---|---|
| `get_balance` | Account balance in USD. |
| `get_profile` | Full account profile. |
| `get_transactions(type:, from:, to:, limit: 50, offset: 0)` | Paginated transaction history. |
| `get_stats(since_days: 30)` | Aggregated usage stats over a lookback window. |

### Browser session (beta, invite-only)

| Method | Purpose |
|---|---|
| `start_manual_registration_session(...)` | Start a country-matched cloud browser session you drive manually via `viewer_url`. |

### Other

| Method | Purpose |
|---|---|
| `check_number(number:)` | Carrier and line-type lookup for an arbitrary E.164 number. Public, no API key. |

### Webhooks

| Method | Purpose |
|---|---|
| `list_webhooks` | List your webhook subscriptions. |
| `create_webhook(url:, events:, description:, threshold:)` | Create a subscription. The `secret` is returned once, on create only; store it immediately. |
| `get_webhook(id:)` | Get one webhook (no secret). |
| `update_webhook(id:, ...)` | Partial update. At least one field required. |
| `delete_webhook(id:)` | Delete a webhook. |
| `test_webhook(id:)` | Fire a synthetic test event through the real dispatcher. |
| `list_webhook_deliveries(id:, limit: 100, offset: 0)` | Recent delivery attempts. |

## Errors

Every non-2xx response raises a subclass of `VirtualSMS::Error`:

| Class | Meaning |
|---|---|
| `VirtualSMS::BadApiKeyError` | Missing or invalid API key. |
| `VirtualSMS::InsufficientBalanceError` | Balance too low for the purchase. |
| `VirtualSMS::NotFoundError` | Resource not found. |
| `VirtualSMS::NoNumbersError` | No stock for the requested service+country. |
| `VirtualSMS::RateLimitedError` | Rate limit exceeded. Never auto-retried. |
| `VirtualSMS::ServerError` | 5xx. `#retryable?` is true only on a GET; a 5xx on a purchase/cancel/rotate call is never auto-retried, verify with a read call before retrying by hand. |
| `VirtualSMS::ApiError` | Any other 4xx. |

```ruby
begin
  client.create_order(service: 'wa', country: 'GB')
rescue VirtualSMS::InsufficientBalanceError => e
  puts "Top up: #{e.message}"
rescue VirtualSMS::NoNumbersError
  puts 'Out of stock, try find_cheapest for an alternative country.'
end
```

GET requests get a bounded, transparent retry (up to 3 attempts, exponential backoff) on network errors and 5xx responses. Mutating requests (POST/PUT/PATCH/DELETE) are never auto-retried by this SDK.

## Why real carrier numbers?

- WhatsApp blocks VoIP numbers
- Telegram flags and restricts VoIP accounts
- Banking apps reject non-mobile numbers
- VirtualSMS uses real physical SIM cards, not VoIP, with 95%+ delivery, public pricing and live availability you can check before you buy

[Learn more](https://virtualsms.io)

## Migrating from v1.x

`v1.x` wrapped the legacy sms-activate-compatible dispatcher. `v2.x` talks to `/api/v1/*` REST endpoints directly and is a breaking change: methods now take keyword arguments (`service:`, `country:`) instead of positional sms-activate-style args, and every method returns a Ruby `Hash` with symbol keys. See `CHANGELOG.md` for the full diff.

## Links

- **Homepage:** [virtualsms.io](https://virtualsms.io)
- **Docs (REST API):** [virtualsms.io/docs](https://virtualsms.io/docs)
- **REST API:** [virtualsms.io/api/v1](https://virtualsms.io/api/v1)
- **Hosted MCP server:** [virtualsms.io/mcp](https://virtualsms.io/mcp)
- **Pricing:** [virtualsms.io/pricing](https://virtualsms.io/pricing)
- **RubyGems:** [rubygems.org/gems/virtualsms-sdk](https://rubygems.org/gems/virtualsms-sdk)
- **GitHub:** [github.com/virtualsms-io](https://github.com/virtualsms-io)

## Ecosystem

- Official MCP registry: `io.github.virtualsms-io/sms`
- [VirtualSMS on Glama](https://glama.ai/mcp/servers)
- [VirtualSMS on Smithery](https://smithery.ai/servers/virtualsms/virtualsms-mcp)
- [VirtualSMS on mcp.so](https://mcp.so/servers/mcp-server-virtualsms-io)
- [virtualsms-mcp on npm](https://www.npmjs.com/package/virtualsms-mcp): hosted MCP server package

## Development

```bash
bundle install
bundle exec rake test
```

Run `sh scripts/check-positioning.sh` before committing copy changes. It fails on stale service or country counts and other banned positioning wording.

## License

MIT
