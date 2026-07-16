# VirtualSMS Ruby SDK

VirtualSMS is an account verification platform that combines real carrier mobile numbers, matching-country proxies and a private cloud browser into one connected workflow.

Built for developers and AI agents: REST API, hosted MCP server, SDKs.

This gem is the Ruby client for the **SMS verification** part of the platform: real physical SIM cards, not VoIP, so codes land on WhatsApp, Telegram, banking apps, and anything else that blocks virtual numbers. Predictable pricing and live number availability are visible before you ever spend a credit.

> **What this SDK does vs. the full platform:** this gem talks to the SMS verification API only (balance, number requests, SMS polling, cancel/complete). Matching-country proxies and the private cloud browser are part of the wider VirtualSMS platform but are **not yet wrapped by this gem**. Use the [REST API](https://virtualsms.io/docs) directly, or the [hosted MCP server](https://virtualsms.io/mcp) if you're driving this from an AI agent. Ruby coverage for proxies/cloud browser is on the roadmap, not shipped yet.

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

# Get your API key at https://virtualsms.io (Settings → API Keys)
client = VirtualSMS.new('vsms_your_api_key')

# Check balance
balance = client.get_balance
puts "Balance: $#{balance}"

# Get a number for WhatsApp verification
activation = client.get_number('wa', country: 22) # 22 = UK
puts "Use this number: #{activation[:phone]}"

# Wait for the verification code
code = client.wait_for_code(activation[:activation_id])
puts "Verification code: #{code}"

# Mark as done
client.done(activation[:activation_id])
```

## Service Codes

| Service | Code |
|---------|------|
| WhatsApp | `wa` |
| Telegram | `tg` |
| Google | `go` |
| Instagram | `ig` |
| Facebook | `fb` |
| Discord | `ds` |
| TikTok | `lf` |
| Twitter/X | `tw` |

2500+ services supported. Full list at [virtualsms.io/services](https://virtualsms.io/services).

## Country Codes

| Country | Code |
|---------|------|
| United States | `187` |
| United Kingdom | `22` |
| Germany | `12` |
| France | `33` |
| Netherlands | `57` |

145+ countries. Full pricing at [virtualsms.io/pricing](https://virtualsms.io/pricing).

## API Reference

### `VirtualSMS.new(api_key, base_url: nil)`
Create a client. Get your API key at [virtualsms.io](https://virtualsms.io).

### `get_balance → Float`
Returns account balance in USD.

### `get_number(service, country: 187) → Hash`
Request a number for verification. Returns `{ activation_id:, phone:, service:, country: }`.

### `get_status(activation_id) → Hash`
Check if SMS arrived. Returns `{ status: 'received', code: '438271' }` when ready.

### `wait_for_code(activation_id, timeout: 300, poll_interval: 5) → String | nil`
Poll automatically until code arrives. Default timeout: 5 minutes.

### `done(activation_id)` / `cancel(activation_id)`
Complete or cancel an activation.

**Note:** this gem covers SMS verification only. Rentals, proxies, and cloud browser sessions are not exposed by any client method above. Reach for the [REST API](https://virtualsms.io/docs) or [hosted MCP server](https://virtualsms.io/mcp) for those.

## Migrating from DaisySMS?

The API is fully compatible with the sms-activate protocol. Change one line:

```ruby
# Before (DaisySMS)
client = VirtualSMS.new('your_key', base_url: 'https://daisysms.com/stubs/handler_api.php')

# After (VirtualSMS)
client = VirtualSMS.new('your_key') # defaults to virtualsms.io
```

## Why Real Carrier Numbers?

- WhatsApp blocks VoIP numbers
- Telegram flags and restricts VoIP accounts
- Banking apps reject non-mobile numbers
- VirtualSMS uses real physical SIM cards, not VoIP, with 95%+ delivery, public pricing and live availability you can check before you buy

[Learn more](https://virtualsms.io)

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

Run `sh scripts/check-positioning.sh` before committing copy changes. It fails on
stale service or country counts and other banned positioning wording.

## License

MIT
