# Changelog

All notable changes to this gem are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] - 2026-07-18

### Breaking change

This is the first REST v1-native major version. `v1.x` wrapped the legacy
`/stubs/handler_api.php` sms-activate-compatible dispatcher; `v2.x` talks to
`https://virtualsms.io/api/v1/*` REST endpoints directly. The legacy PHP
dispatcher is not used by v2 at all. If you're on `v1.x`, this is not a
drop-in upgrade: `create_order`/`get_order`/etc. now take `service:`/
`country:` ISO codes and keyword args instead of the sms-activate-style
positional `service, country: 187` shape, and every method now returns a
Ruby `Hash` (symbol keys) instead of a raw parsed response string.

### Added

- Full REST v1 coverage: activations/orders, rentals (Full Access + Platform
  tier), proxies, account, one manual-registration-session starter, a public
  number-check tool, and webhooks (new surface, not present in `v1.x` at all).
- Typed error hierarchy: `VirtualSMS::Error` base with
  `BadApiKeyError`, `InsufficientBalanceError`, `NotFoundError`,
  `NoNumbersError`, `RateLimitedError`, `ServerError` (retryable on GET
  only), `ApiError`.
- Idempotency: every mutating request auto-sends a fresh `X-Idempotency-Key`.
- Bounded GET-only retry (max 3 attempts, exponential backoff) for transient
  network errors and 5xx responses. Mutating calls are never auto-retried.
- Client-side helpers matching the MCP server's tool contract: `get_sms`,
  `wait_for_sms`, `order_history`, `cancel_all_orders`, `search_services`,
  `find_cheapest`, `get_stats`, `generate_proxy_endpoint`.
- `wait_for_sms` polling loop (WebSocket race is optional per the SDK spec
  and not implemented in this v2.0.0 baseline; may land in a later minor).

### Removed

- The `net-http` runtime dependency (bogus in `v1.0.0`: `net/http` is Ruby
  standard library, never a separate gem).
- The sms-activate "drop-in replacement" framing. This SDK is now positioned
  as a native VirtualSMS REST API v1 client, not a DaisySMS/sms-activate
  migration path.

## [1.0.0] - 2026-07-16

Initial release. Legacy `/stubs/handler_api.php` client: `get_balance`,
`get_number`, `get_status`, `done`, `cancel`, `wait_for_code`.
