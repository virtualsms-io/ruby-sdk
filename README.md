# VirtualSMS Ruby SDK

Ruby client for [VirtualSMS](https://virtualsms.io) — SMS verification using real physical SIM cards.

Unlike VoIP-based services, VirtualSMS uses real SIM cards in hardware modems connected to European and US cellular networks. Near-100% delivery rates on platforms like WhatsApp, Telegram, and banking apps that block virtual numbers.

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

700+ services supported. Full list at [virtualsms.io/services](https://virtualsms.io/services).

## Country Codes

| Country | Code |
|---------|------|
| United States | `187` |
| United Kingdom | `22` |
| Germany | `12` |
| France | `33` |
| Netherlands | `57` |

30+ countries. Full pricing at [virtualsms.io/pricing](https://virtualsms.io/pricing).

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

## Migrating from DaisySMS?

The API is fully compatible with the sms-activate protocol. Change one line:

```ruby
# Before (DaisySMS)
client = VirtualSMS.new('your_key', base_url: 'https://daisysms.com/stubs/handler_api.php')

# After (VirtualSMS)
client = VirtualSMS.new('your_key') # defaults to virtualsms.io
```

## Why Real SIM Cards?

- WhatsApp blocks 90%+ of VoIP numbers
- Telegram flags and restricts VoIP accounts
- Banking apps reject non-mobile numbers
- VirtualSMS uses physical SIM cards = real carrier numbers = near-100% delivery

[Learn more](https://virtualsms.io)

## Links

- **Website:** [virtualsms.io](https://virtualsms.io)
- **API Docs:** [virtualsms.io/api](https://virtualsms.io/api)
- **Pricing:** [virtualsms.io/pricing](https://virtualsms.io/pricing)
- **RubyGems:** [rubygems.org/gems/virtualsms-sdk](https://rubygems.org/gems/virtualsms-sdk)
- **GitHub:** [github.com/virtualsms-io](https://github.com/virtualsms-io)

## License

MIT
