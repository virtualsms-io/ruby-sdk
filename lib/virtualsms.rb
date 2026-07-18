require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'time'

require_relative 'virtualsms/version'
require_relative 'virtualsms/errors'
require_relative 'virtualsms/platform_tier_country_ids'

# VirtualSMS Ruby SDK: a native client for the VirtualSMS REST API v1.
#
# VirtualSMS is an account verification platform that combines real carrier
# mobile numbers, matching-country proxies and a private cloud browser into
# one connected workflow, behind one API key and one prepaid balance.
#
# Get your API key at https://virtualsms.io (Settings -> API Keys).
# Full REST reference: https://virtualsms.io/docs
#
# @example Quick start
#   client = VirtualSMS.new(ENV.fetch('VIRTUALSMS_API_KEY'))
#   order  = client.create_order(service: 'wa', country: 'GB')
#   result = client.wait_for_sms(order_id: order[:order_id])
#   puts result[:code] if result[:success]
class VirtualSMS
  DEFAULT_BASE_URL = ENV.fetch('VIRTUALSMS_BASE_URL', 'https://virtualsms.io/api/v1')

  # 1 initial attempt + up to 2 retries, GET/HEAD only.
  GET_RETRY_MAX_ATTEMPTS = 3
  GET_RETRY_BASE_DELAY = 0.3 # seconds; backoff is BASE * 2**(attempt-1)

  PROXY_HTTP_PORT = 823
  PROXY_SOCKS5_PORT = 824

  ACTIVE_ORDER_STATUSES = %w[waiting pending sms_received created].freeze

  # @param api_key [String, nil] Get one at https://virtualsms.io. Optional:
  #   several endpoints (catalog/pricing/public lookups) don't require it,
  #   but any authenticated method raises BadApiKeyError without one.
  # @param base_url [String] overridable via the VIRTUALSMS_BASE_URL env var.
  # @param timeout [Integer] request open+read timeout in seconds (default 30).
  def initialize(api_key = nil, base_url: DEFAULT_BASE_URL, timeout: 30)
    @api_key = api_key
    @base_url = base_url.to_s.chomp('/')
    uri = URI.parse(@base_url)
    @http = Net::HTTP.new(uri.host, uri.port)
    @http.use_ssl = (uri.scheme == 'https')
    @http.open_timeout = timeout
    @http.read_timeout = timeout
  end

  attr_reader :api_key, :base_url

  # ─── 2.1 Activations / Orders ──────────────────────────────────────────

  # List all SMS-verification services (Telegram, WhatsApp, etc). Public.
  def list_services
    raw = http_request(:get, '/customer/services')
    items = raw.is_a?(Array) ? raw : (raw[:services] || [])
    items.map do |s|
      { code: (s[:service_id] || s[:code]).to_s, name: (s[:service_name] || s[:name]).to_s, icon: s[:icon] }
    end
  end

  # List all available countries. Public.
  def list_countries
    raw = http_request(:get, '/customer/countries')
    items = raw.is_a?(Array) ? raw : (raw[:countries] || [])
    items.map do |c|
      { iso: (c[:country_id] || c[:iso]).to_s, name: (c[:country_name] || c[:name]).to_s, flag: c[:flag] }
    end
  end

  # Check price + REAL stock for a service+country combo. Public.
  #
  # /price alone returns no availability field, so this fails closed: real
  # stock is derived from the catalog's per-country `count` (count > 0 = in
  # stock), the same source the website uses. Never trust `available: true`
  # off a single /price call.
  def get_price(service:, country:)
    begin
      raw = http_request(:get, '/price', params: { service: service, country: country })
    rescue NotFoundError
      return { available: false, message: 'Service/country combination not available' }
    end

    price = {
      price_usd: to_f(raw[:price] || raw[:price_usd]),
      currency: (raw[:currency] || 'USD').to_s,
      available: false
    }

    begin
      row = catalog_countries(service: service).find { |c| c[:iso].to_s.upcase == country.to_s.upcase }
      price[:available] = !!row && row[:count].to_i > 0
    rescue StandardError
      # Keep the fail-closed default (false) if the catalog lookup errors.
    end

    return { available: false, message: 'Service/country combination not available' } unless price[:available]

    price
  end

  # Buy a virtual number for one-off SMS verification. Requires api_key.
  def create_order(service:, country:)
    require_api_key!
    raw = http_request(:post, '/customer/purchase', body: { service: service, country: country })
    normalize_order(raw)
  end

  # Full order detail including any received SMS. Requires api_key.
  def get_order(order_id:)
    require_api_key!
    raw = http_request(:get, "/customer/order/#{esc(order_id)}")
    normalize_order(raw)
  end

  # Poll for SMS delivery on an order (thin wrapper over get_order that
  # normalizes messages/legacy sms_code/sms_text into one shape and extracts
  # the numeric code). Requires api_key.
  def get_sms(order_id:)
    order = get_order(order_id: order_id)
    messages = normalize_messages(order)
    first_content = messages[0] && messages[0][:content]
    code = order[:sms_code] || (first_content && extract_code(first_content))

    result = { status: order[:status], phone_number: order[:phone_number] }
    result[:messages] = messages unless messages.empty?
    if code
      result[:code] = code
      result[:sms_code] = code
    end
    result[:sms_text] = first_content if first_content
    result
  end

  # Block until an SMS arrives on the order or timeout elapses. Polling-only
  # in this SDK (no WebSocket race) - an acceptable v2.0.0 baseline per the
  # SDK spec; WS can land in a later minor. Requires api_key.
  #
  # Defaults intentionally differ from the MCP tool's own defaults
  # (60s/max 600s): a human or script blocking on this call, not an LLM
  # agent loop, is the typical SDK caller, so the default is more generous.
  #
  # @return [Hash] on success: {success: true, order_id:, phone_number:,
  #   status: "sms_received", messages:, code:, delivery_method: "polling",
  #   elapsed_seconds:, poll_attempts:}. On timeout (never raises):
  #   {success: false, error: "timeout", order_id:, phone_number:}.
  def wait_for_sms(order_id:, timeout_seconds: 300, interval_seconds: 5)
    require_api_key!
    start = Time.now
    initial = get_order(order_id: order_id)
    phone_number = initial[:phone_number]

    build_success = lambda do |messages, delivery_method, poll_attempts = nil|
      first_content = (messages[0] && messages[0][:content]) || ''
      code = extract_code(first_content)
      result = {
        success: true,
        order_id: order_id,
        phone_number: phone_number,
        status: 'sms_received',
        messages: messages,
        code: code,
        sms_code: code,
        sms_text: first_content,
        delivery_method: delivery_method,
        elapsed_seconds: (Time.now - start).round
      }
      result[:poll_attempts] = poll_attempts if poll_attempts
      result
    end

    initial_messages = normalize_messages(initial)
    return build_success.call(initial_messages, 'instant') unless initial_messages.empty?

    attempts = 0
    loop do
      attempts += 1
      status = get_order(order_id: order_id)
      messages = normalize_messages(status)
      return build_success.call(messages, 'polling', attempts) unless messages.empty?

      if %w[cancelled failed].include?(status[:status].to_s)
        raise Error, "Order #{order_id} was #{status[:status]} before SMS arrived."
      end

      remaining = timeout_seconds - (Time.now - start)
      break if remaining <= 0

      sleep([interval_seconds, remaining].min)
    end

    {
      success: false,
      error: 'timeout',
      order_id: order_id,
      phone_number: phone_number
    }
  end

  # Cancel + refund an order (before any SMS received). Requires api_key.
  #
  # Pre-checks cancel_available_at from a fresh get_order call and
  # short-circuits with a cooldown_active Hash (not an exception) if the
  # 120s post-purchase cooldown hasn't elapsed yet - saves a round trip.
  # Best-effort: if the pre-check lookup fails, the backend call still fires
  # and enforces the cooldown itself.
  def cancel_order(order_id:)
    require_api_key!
    begin
      order = get_order(order_id: order_id)
      blocked = precheck_cooldown(order[:cancel_available_at], :cancel)
      return blocked if blocked
    rescue StandardError
      # Lookup failed. Let the backend handle it.
    end

    raw = http_request(:post, "/customer/cancel/#{esc(order_id)}")
    { success: !!raw[:success], refunded: !!raw[:refunded] }
  end

  # Get a new number for the same service/country, no extra charge.
  # Requires api_key. Same cooldown pre-check pattern as cancel_order.
  def swap_number(order_id:)
    require_api_key!
    begin
      order = get_order(order_id: order_id)
      blocked = precheck_cooldown(order[:swap_available_at], :swap)
      return blocked if blocked
    rescue StandardError
      # Lookup failed. Let the backend handle it.
    end

    raw = http_request(:post, "/customer/swap/#{esc(order_id)}")
    normalize_order(raw)
  end

  # Ask the provider to resend the SMS to the SAME number (not a new number;
  # see swap_number for that). Requires api_key.
  def retry_order(order_id:)
    require_api_key!
    raw = http_request(:post, "/orders/#{esc(order_id)}/retry")
    { success: !!raw[:success], order_id: (raw[:order_id] || order_id).to_s, message: raw[:message].to_s }
  end

  # List orders, optional status filter. Requires api_key. A 404 from this
  # endpoint (may not exist on older deployments) is swallowed to [].
  def list_orders(status: nil)
    require_api_key!
    begin
      raw = http_request(:get, '/customer/orders', params: status ? { status: status } : nil)
    rescue NotFoundError
      return []
    end
    items = raw.is_a?(Array) ? raw : (raw[:orders] || [])
    items.map { |o| normalize_list_order(o) }
  end

  # Order history with client-side filtering (service/country/since_days)
  # over list_orders, plus a hard result cap. Requires api_key.
  def order_history(status: nil, service: nil, country: nil, since_days: nil, limit: 20)
    limit = [(limit || 20), 50].min
    orders = list_orders(status: status)
    cutoff = since_days ? (Time.now - (since_days * 86_400)) : nil
    service_filter = service&.downcase
    country_filter = country&.upcase

    filtered = orders.select do |o|
      next false if cutoff && !(parse_time(o[:created_at]) && parse_time(o[:created_at]) >= cutoff)
      next false if service_filter && o[:service].to_s.downcase != service_filter
      next false if country_filter && o[:country].to_s.upcase != country_filter

      true
    end

    capped = filtered.first(limit)

    {
      count: capped.length,
      total_matched: filtered.length,
      filters: { status: status, service: service, country: country, since_days: since_days },
      orders: capped.map { |o| o.slice(:order_id, :phone_number, :service, :country, :price, :status, :created_at, :sms_code) }
    }
  end

  # Bulk-cancel every active order. Requires api_key. Never aborts on the
  # first failure: gathers every result (success or error) before returning.
  def cancel_all_orders
    require_api_key!
    orders = list_orders
    active = orders.select { |o| ACTIVE_ORDER_STATUSES.include?(o[:status].to_s) }

    if active.empty?
      return { cancelled: 0, failed: 0, total_active: 0, cancelled_orders: [], failures: [] }
    end

    cancelled = []
    failures = []

    active.each do |o|
      begin
        result = cancel_order(order_id: o[:order_id])
        if result[:error] == 'cooldown_active'
          failures << { order_id: o[:order_id], error: result[:message] }
        else
          cancelled << { order_id: o[:order_id], refunded: !!result[:refunded] }
        end
      rescue StandardError => e
        failures << { order_id: o[:order_id], error: e.message }
      end
    end

    {
      cancelled: cancelled.length,
      failed: failures.length,
      total_active: active.length,
      cancelled_orders: cancelled,
      failures: failures
    }
  end

  # Find the right service code using natural language ("uber", "binance",
  # "steam"). Client-side fuzzy match over list_services; no dedicated
  # backend search route.
  def search_services(query:)
    services = list_services
    q = query.to_s.downcase.strip

    scored = services.map do |s|
      name = s[:name].to_s.downcase
      code = s[:code].to_s.downcase
      score =
        if code == q || name == q
          1.0
        elsif code.start_with?(q) || name.start_with?(q)
          0.9
        elsif code.include?(q) || name.include?(q)
          0.7
        else
          query_tokens = q.split(/\s+/)
          name_tokens = name.split(/[\s_-]+/)
          matches = query_tokens.count { |qt| name_tokens.any? { |nt| nt.include?(qt) || qt.include?(nt) } }
          matches.positive? ? (matches.to_f / [query_tokens.length, name_tokens.length].max) * 0.6 : 0.0
        end

      { code: s[:code], name: s[:name], match_score: (score * 100).round / 100.0 }
    end

    matches = scored.select { |s| s[:match_score] >= 0.5 }.sort_by { |s| -s[:match_score] }.first(5)

    if matches.empty?
      { query: query, matches: [], message: 'No matching services found', tip: 'Try list_services to browse all available services.' }
    else
      { query: query, matches: matches, tip: 'Use the "code" field as the service parameter in other methods.' }
    end
  end

  # Find the cheapest in-stock countries for a service, sorted by price.
  # Client-side over the catalog (same real-stock source get_price uses),
  # never a fan-out over /price per country.
  def find_cheapest(service:, limit: 5)
    catalog = catalog_countries(service: service)
    results = catalog.select { |c| c[:count].to_i.positive? }
                      .map { |c| { country: c[:iso], country_name: c[:name], price_usd: c[:price_usd], stock: true } }
                      .sort_by { |r| r[:price_usd] }
    top = results.first(limit)

    if top.empty?
      return {
        service: service,
        cheapest_options: [],
        total_available_countries: 0,
        message: "No countries available for service \"#{service}\". Use search_services to verify the service code, or list_services to see all available services."
      }
    end

    { service: service, cheapest_options: top, total_available_countries: results.length }
  end

  # ─── 2.2 Rentals ────────────────────────────────────────────────────────
  # Two tiers, both refund-identical (full refund within 20 min of purchase,
  # before first SMS): full_access (local SIM inventory, any service) and
  # platform (global supplier network, one service per number, 24/72/168h
  # durations only).

  # List raw Full-Access pricing tiers (catalog dump, not authoritative for
  # what's purchasable today). Public.
  def rentals_pricing
    raw = http_request(:get, '/rentals/pricing')
    raw.is_a?(Array) ? raw : []
  end

  # List country availability + pricing per tier. Public.
  def rentals_available(country: nil, service: nil, type: nil, tier: nil)
    params = { country: country, service: service, type: type }
    params[:provider] = 'network' if tier.to_s == 'platform'
    http_request(:get, '/rentals/available', params: params)
  end

  # List platform-tier services available in a country with stock + retail
  # price. Public. Explicit field allowlist: never forwards an internal
  # supplier-code field the backend response may include.
  def rentals_services(country_code:, duration_hours: 24)
    raw = http_request(:get, '/rentals/services', params: { country_code: country_code, duration: duration_hours })
    items = raw.is_a?(Array) ? raw : []
    items.map do |s|
      {
        service_id: s[:service_id].to_s,
        service_name: s[:service_name].to_s,
        physical_count: (s[:physical_count] || 0).to_i,
        our_price: s[:our_price].nil? ? nil : to_f(s[:our_price]),
        base_price: s[:base_price].nil? ? nil : to_f(s[:base_price]),
        popular: !!s[:popular],
        icon_url: s[:icon_url]
      }
    end
  end

  # Get the catalog price for a (service, country, duration) platform-tier
  # combo. Public.
  def rentals_price(service:, country_code:, duration_hours:)
    http_request(:get, '/rentals/price', params: { service: service, country_code: country_code, duration: duration_hours })
  end

  # Create a rental in either tier. Requires api_key.
  #
  # tier: "full_access" -> local SIM inventory, any service, POST /rentals.
  #   rental_type is inferred: "service" when `service` is given, else "full".
  # tier: "platform" -> resolves country_code (ISO-2) to the internal
  #   numeric ID via PLATFORM_TIER_COUNTRY_IDS, then POST /rentals/provider.
  #   `service` is required for this tier.
  def create_rental(tier:, country:, duration_hours:, service: nil, auto_renew: false)
    require_api_key!

    case tier.to_s
    when 'full_access'
      http_request(:post, '/rentals', body: {
        country: country,
        rental_type: service ? 'service' : 'full',
        duration_hours: duration_hours,
        service: service,
        auto_renew: auto_renew
      })
    when 'platform'
      raise ArgumentError, 'service is required for tier: "platform"' unless service

      country_id = PLATFORM_TIER_COUNTRY_IDS[country.to_s.upcase]
      if country_id.nil?
        raise Error, "Platform-tier rentals are not available for country_code \"#{country}\". Use rentals_available with tier: \"platform\" to see supported countries."
      end

      raw = http_request(:post, '/rentals/provider', body: {
        service: service,
        country: country_id,
        duration_hours: duration_hours,
        provider: 'network'
      })

      {
        success: raw.key?(:success) ? !!raw[:success] : true,
        rental_id: raw[:rental_id].to_s,
        phone_number: raw[:phone_number].to_s,
        expires_at: raw[:expires_at].to_s,
        retail_cost: raw[:retail_cost].nil? ? nil : to_f(raw[:retail_cost]),
        currency: raw[:currency],
        status: 'active'
      }
    else
      raise ArgumentError, "tier must be \"full_access\" or \"platform\", got #{tier.inspect}"
    end
  end

  # List rentals, optional status filter. Requires api_key.
  def list_rentals(status: nil)
    require_api_key!
    raw = http_request(:get, '/rentals', params: status ? { status: status } : nil)
    raw.is_a?(Array) ? raw : []
  end

  # Get one rental by id. Client-side: no dedicated GET-by-id backend route
  # exists, so this calls list_rentals(status: "all") and finds locally.
  # Requires api_key. Returns nil if not found.
  def get_rental(rental_id:)
    require_api_key!
    list_rentals(status: 'all').find { |r| r[:id].to_s == rental_id.to_s }
  end

  # Extend an active rental, charged at current catalog price. Requires api_key.
  def extend_rental(rental_id:, duration_hours:)
    require_api_key!
    http_request(:post, "/rentals/#{esc(rental_id)}/extend", body: { duration_hours: duration_hours })
  end

  # Full refund: only eligible within 20 minutes of purchase and before the
  # first SMS, either tier. Requires api_key.
  def cancel_rental(rental_id:)
    require_api_key!
    http_request(:post, "/rentals/#{esc(rental_id)}/cancel", body: {})
  end

  # ─── 2.3 Proxies ────────────────────────────────────────────────────────

  # List pool types, countries, price/GB. Public, ~10min cache upstream.
  def list_proxy_catalog
    raw = http_request(:get, '/proxies/catalog')
    pool_types = raw.is_a?(Hash) ? (raw[:pool_types] || []) : (raw.is_a?(Array) ? raw : [])
    pool_types.map do |p|
      {
        id: p[:id].to_s,
        label: p[:label].to_s,
        price_per_gb: to_f(p[:price_per_gb]),
        countries: (p[:countries] || []).map do |c|
          { code: c[:code].to_s, name: c[:name].to_s, available: !!c[:available], ip_count: (c[:ip_count] || 0).to_i }
        end
      }
    end
  end

  # List owned proxies with credentials. Requires api_key.
  def list_proxies
    require_api_key!
    raw = http_request(:get, '/proxies')
    items = raw.is_a?(Array) ? raw : []
    items.map do |p|
      {
        proxy_id: p[:proxy_id].to_s,
        pool_type: p[:pool_type].to_s,
        country_code: p[:country_code].to_s,
        country_name: p[:country_name],
        gb_total: to_f(p[:gb_total]),
        gb_used: to_f(p[:gb_used]),
        gb_remaining: to_f(p[:gb_remaining]),
        proxy_host: p[:proxy_host].to_s,
        proxy_port: (p[:proxy_port] || 0).to_i,
        proxy_login: p[:proxy_login].to_s,
        proxy_password: p[:proxy_password].to_s,
        updated_at: p[:updated_at],
        created_at: p[:created_at]
      }
    end
  end

  # Purchase proxy traffic (GB) for a pool type. Requires api_key.
  def buy_proxy(pool_type:, gb:, country_code: nil, idempotency_key: nil)
    require_api_key!
    http_request(:post, '/proxies', body: {
      pool_type: pool_type, gb: gb, country_code: country_code, idempotency_key: idempotency_key
    })
  end

  # Get a fresh exit IP for an existing proxy. Requires api_key.
  def rotate_proxy(proxy_id:, port: nil)
    require_api_key!
    body = port ? { port: port } : {}
    http_request(:post, "/proxies/#{esc(proxy_id)}/rotate", body: body)
  end

  # Cached GB used/remaining (refreshed ~5min, no upstream call). Requires api_key.
  def get_proxy_usage(proxy_id:)
    require_api_key!
    raw = http_request(:get, "/proxies/#{esc(proxy_id)}/usage")
    { gb_used: to_f(raw[:gb_used]), gb_remaining: to_f(raw[:gb_remaining]), requests: (raw[:requests] || 0).to_i, updated_at: raw[:updated_at] }
  end

  # Per-day GB/requests series, 7d or 30d. Requires api_key.
  def get_proxy_usage_history(proxy_id:, range: '7d')
    require_api_key!
    raw = http_request(:get, "/proxies/#{esc(proxy_id)}/usage-history", params: { range: range })
    series = (raw[:series] || []).map { |p| { date: p[:date].to_s, gb: to_f(p[:gb]), requests: (p[:requests] || 0).to_i } }
    totals = raw[:totals] || {}
    { series: series, totals: { gb: to_f(totals[:gb]), requests: (totals[:requests] || 0).to_i } }
  end

  # Persist default geo-targeting on a proxy sub-user. Requires api_key.
  # Country-only is free; cities/asns bill the customer's own funded GB at
  # 2x on non-premium pools (free on residential_premium) - the response's
  # premium_2x field reflects this.
  def set_proxy_targeting(proxy_id:, country_code:, cities: nil, asns: nil)
    require_api_key!
    raw = http_request(:post, "/proxies/#{esc(proxy_id)}/targeting", body: {
      country_code: country_code, cities: cities, asns: asns
    })
    { ok: !!raw[:ok], country_code: (raw[:country_code] || country_code).to_s, premium_2x: !!raw[:premium_2x] }
  end

  # Dial out through the proxy, report exit IP/country/city/ISP/latency.
  # Requires api_key. Rate-limited ~1/20s per proxy upstream.
  def test_proxy(proxy_id:, country:, session: nil, protocol: nil)
    require_api_key!
    raw = http_request(:post, "/proxies/#{esc(proxy_id)}/test", body: {
      country: country, session: session, protocol: protocol
    })
    {
      ok: !!raw[:ok], exit_ip: raw[:exit_ip], country_code: raw[:country_code], country_name: raw[:country_name],
      city: raw[:city], region: raw[:region], isp: raw[:isp], asn: raw[:asn],
      latency_ms: raw[:latency_ms], error: raw[:error]
    }
  end

  # Discover valid cities/states/asns/zips for a pool_type+country. Public,
  # 6h cache upstream. NOT available for pool_type "residential_premium".
  def list_proxy_locations(pool_type:, country:, kind:)
    raw = http_request(:get, '/proxies/locations', params: { pool_type: pool_type, country: country, kind: kind })
    items = raw.is_a?(Hash) ? (raw[:items] || []) : []
    items.map { |it| { code: it[:code].to_s, name: it[:name].to_s, count: (it[:count] || 0).to_i } }
  end

  # Compose a ready-to-use proxy connection string. Pure function, no
  # backend call, no purchase: looks up the proxy's credentials via
  # list_proxies, then builds a username string encoding targeting exactly
  # as the frontend's ProxyEndpointGenerator does. Requires api_key (needed
  # for the list_proxies lookup).
  def generate_proxy_endpoint(proxy_id:, country_code:, target_by: 'country', location_code: nil,
                               session: 'rotating', sticky_ttl_minutes: 10, count: 1,
                               protocol: 'HTTP', format: 'host:port:user:pass')
    require_api_key!
    proxy = list_proxies.find { |p| p[:proxy_id].to_s == proxy_id.to_s }
    raise NotFoundError, "Not found: proxy #{proxy_id} does not exist on this account" unless proxy

    count = [[count.to_i, 1].max, 100].min
    port = protocol.to_s.upcase == 'SOCKS5' ? PROXY_SOCKS5_PORT : PROXY_HTTP_PORT
    premium_2x = target_by.to_s != 'country' && !location_code.to_s.strip.empty? && proxy[:pool_type] != 'residential_premium'

    endpoints =
      if session.to_s == 'sticky'
        Array.new(count) do |i|
          user = build_proxy_username(proxy[:proxy_login], country_code, target_by, location_code, i + 1, sticky_ttl_minutes)
          build_proxy_endpoint_string(proxy[:proxy_host], port, user, proxy[:proxy_password], format, protocol)
        end
      else
        user = build_proxy_username(proxy[:proxy_login], country_code, target_by, location_code)
        endpoint = build_proxy_endpoint_string(proxy[:proxy_host], port, user, proxy[:proxy_password], format, protocol)
        Array.new(count) { endpoint }
      end

    {
      proxy_id: proxy[:proxy_id],
      pool_type: proxy[:pool_type],
      host: proxy[:proxy_host],
      port: port,
      protocol: protocol.to_s.upcase,
      session: session.to_s,
      sticky_ttl_minutes: session.to_s == 'sticky' ? sticky_ttl_minutes : nil,
      country_code: country_code,
      target_by: target_by.to_s,
      location_code: location_code,
      premium_2x: premium_2x,
      endpoints: endpoints
    }
  end

  # ─── 2.4 Account ────────────────────────────────────────────────────────

  # Check account balance. Requires api_key.
  def get_balance
    require_api_key!
    raw = http_request(:get, '/customer/balance')
    { balance_usd: to_f(raw[:balance_usd] || raw[:balance]) }
  end

  # Full account profile. Requires api_key.
  def get_profile
    require_api_key!
    raw = http_request(:get, '/customer/profile')
    {
      id: raw[:id].to_s,
      email: raw[:email].to_s,
      telegram_linked: !!raw[:telegram_linked],
      telegram_username: raw[:telegram_username],
      balance_usd: to_f(raw[:balance_usd]),
      total_spent_usd: to_f(raw[:total_spent_usd]),
      total_credits_usd: to_f(raw[:total_credits_usd]),
      total_orders: (raw[:total_orders] || 0).to_i,
      active_api_keys: (raw[:active_api_keys] || 0).to_i,
      created_at: raw[:created_at]
    }
  end

  # Paginated transaction history. Requires api_key.
  def get_transactions(type: nil, from: nil, to: nil, limit: 50, offset: 0)
    require_api_key!
    raw = http_request(:get, '/customer/transactions', params: { type: type, from: from, to: to, limit: limit, offset: offset })
    items = raw[:transactions] || []
    {
      count: (raw[:count] || items.length).to_i,
      limit: (raw[:limit] || 0).to_i,
      offset: (raw[:offset] || 0).to_i,
      transactions: items.map do |t|
        {
          id: t[:id].to_s, amount: to_f(t[:amount]), type: t[:type].to_s, description: t[:description],
          order_id: t[:order_id], balance_before: to_f(t[:balance_before]), balance_after: to_f(t[:balance_after]),
          created_at: t[:created_at]
        }
      end
    }
  end

  # Aggregated usage stats over a lookback window. Client-side: calls
  # get_balance + list_orders, then aggregates locally. Requires api_key.
  def get_stats(since_days: 30)
    require_api_key!
    cutoff = Time.now - (since_days * 86_400)
    balance = get_balance
    orders = list_orders

    in_window = orders.select { |o| (t = parse_time(o[:created_at])) && t >= cutoff }

    by_status = Hash.new(0)
    by_service = Hash.new(0)
    by_country = Hash.new(0)
    total_spend = 0.0
    successful = 0
    terminal = 0

    in_window.each do |o|
      by_status[o[:status].to_s] += 1
      by_service[o[:service].to_s] += 1 if o[:service] && !o[:service].to_s.empty?
      by_country[o[:country].to_s] += 1 if o[:country] && !o[:country].to_s.empty?
      total_spend += o[:price].to_f if o[:status].to_s != 'cancelled' && o[:price]

      if %w[completed sms_received expired cancelled].include?(o[:status].to_s)
        terminal += 1
        successful += 1 if %w[completed sms_received].include?(o[:status].to_s)
      end
    end

    top_entries = lambda do |h, n = 5|
      h.sort_by { |_, v| -v }.first(n).map { |k, v| { key: k, count: v } }
    end

    {
      window_days: since_days,
      balance_usd: balance[:balance_usd],
      total_orders: in_window.length,
      successful_orders: successful,
      success_rate: terminal.positive? ? ((successful.to_f / terminal) * 1000).round / 10.0 : nil,
      total_spend_usd: (total_spend * 100).round / 100.0,
      status_breakdown: by_status,
      top_services: top_entries.call(by_service),
      top_countries: top_entries.call(by_country),
      note: orders.length >= 50 ? 'Server caps order history at 50 rows. Stats may undercount if your activity exceeds 50 orders in the window.' : nil
    }
  end

  # ─── 2.5 Session ────────────────────────────────────────────────────────

  # Start a country-matched cloud browser session the caller drives manually
  # via the returned viewer_url. Requires api_key. Beta, invite-only: a
  # 403/404/503 from the backend is caught and re-raised as a clean
  # "join the beta" Error rather than a raw HTTP error.
  def start_manual_registration_session(service_name: nil, country: nil, device_mode: nil, with_proxy: nil,
                                         target_url: nil, order_id: nil, mode: 'fresh')
    require_api_key!
    with_proxy = with_proxy.nil? ? !country.nil? : with_proxy

    raw =
      begin
        http_request(:post, '/browser-sessions/start', body: {
          serviceName: service_name, country: country, deviceMode: device_mode, withProxy: with_proxy,
          targetUrl: target_url, orderId: order_id, mode: mode
        })
      rescue Error => e
        if session_unavailable?(e)
          raise Error, 'Manual registration sessions are an invite-only beta. Join https://t.me/VirtualSMS_io for access.'
        end

        raise
      end

    session = raw[:session] || raw
    {
      id: session[:id].to_s,
      status: session[:status].to_s,
      service_name: session[:service_name],
      country_code: session[:country_code],
      device_mode: session[:device_mode],
      with_proxy: session[:with_proxy],
      viewer_url: session[:viewer_url],
      target_url: session[:target_url],
      order_id: session[:order_id],
      phone_number: session[:phone_number],
      timeline: session[:timeline]
    }
  end

  # ─── 2.6 Other ──────────────────────────────────────────────────────────

  # Carrier + line-type lookup for an arbitrary E.164 number. Public, no api_key.
  def check_number(number:)
    raw = http_request(:get, '/tools/number-check', params: { number: number })
    {
      valid: !!raw[:valid], e164: raw[:e164].to_s, national: raw[:national], country_code: raw[:country_code].to_s,
      country_name: raw[:country_name].to_s, country_prefix: raw[:country_prefix], location: raw[:location],
      carrier: raw[:carrier], line_type: raw[:line_type].to_s, spam_risk: raw[:spam_risk].to_s,
      cached: !!raw[:cached], message: raw[:message]
    }
  end

  # ─── 2.7 Webhooks ───────────────────────────────────────────────────────

  # List the account's webhook subscriptions. Requires api_key.
  def list_webhooks
    require_api_key!
    raw = http_request(:get, '/customer/webhooks')
    { success: !!raw[:success], webhooks: raw[:webhooks] || [], count: (raw[:count] || 0).to_i }
  end

  # Create a webhook subscription. Requires api_key. `url` MUST be https://,
  # no localhost/IP literals. `threshold` is required when `events`
  # includes "balance.low". The response's `secret` is returned exactly
  # once, on create only - store it immediately, it can't be retrieved again.
  def create_webhook(url:, events:, description: nil, threshold: nil)
    require_api_key!
    http_request(:post, '/customer/webhooks', body: {
      url: url, description: description, events: events, threshold: threshold
    })
  end

  # Get one webhook (no secret). Requires api_key.
  def get_webhook(id:)
    require_api_key!
    http_request(:get, "/customer/webhooks/#{esc(id)}")
  end

  # Partial update (url/description/events/threshold/active/paused).
  # Requires api_key and at least one field. Un-pausing (paused: false when
  # previously true) resets failure_count_consecutive to 0 server-side.
  def update_webhook(id:, url: nil, description: nil, events: nil, threshold: nil, active: nil, paused: nil)
    require_api_key!
    body = { url: url, description: description, events: events, threshold: threshold, active: active, paused: paused }.compact
    raise ArgumentError, 'update_webhook requires at least one field to update' if body.empty?

    http_request(:patch, "/customer/webhooks/#{esc(id)}", body: body)
  end

  # Delete a webhook. Requires api_key.
  def delete_webhook(id:)
    require_api_key!
    http_request(:delete, "/customer/webhooks/#{esc(id)}")
  end

  # Fire a synthetic test event through the real dispatcher. Requires
  # api_key and the webhook to be active and not paused.
  def test_webhook(id:)
    require_api_key!
    http_request(:post, "/customer/webhooks/#{esc(id)}/test", body: {})
  end

  # List recent delivery attempts for a webhook. Requires api_key.
  def list_webhook_deliveries(id:, limit: 100, offset: 0)
    require_api_key!
    http_request(:get, "/customer/webhooks/#{esc(id)}/deliveries", params: { limit: limit, offset: offset })
  end

  private

  # ─── HTTP layer ─────────────────────────────────────────────────────────

  def require_api_key!
    return if @api_key && !@api_key.to_s.empty?

    raise BadApiKeyError, 'An API key is required for this operation. Get your API key at https://virtualsms.io'
  end

  def http_request(method, path, params: nil, body: nil)
    uri = build_uri(path, params)
    attempt = 0

    loop do
      attempt += 1
      request = build_request(method, uri, body)

      response =
        begin
          @http.request(request)
        rescue StandardError => e
          if get_or_head?(method) && attempt < GET_RETRY_MAX_ATTEMPTS
            sleep(retry_delay(attempt))
            next
          end
          raise Error, "VirtualSMS request failed: #{e.message}"
        end

      status = response.code.to_i

      if status >= 500 && get_or_head?(method) && attempt < GET_RETRY_MAX_ATTEMPTS
        sleep(retry_delay(attempt))
        next
      end

      return parse_response(response, status, method)
    end
  end

  def get_or_head?(method)
    method == :get || method == :head
  end

  def retry_delay(attempt_number)
    GET_RETRY_BASE_DELAY * (2**(attempt_number - 1))
  end

  def build_uri(path, params)
    uri = URI.parse("#{@base_url}#{path}")
    if params
      clean = params.reject { |_, v| v.nil? }
      uri.query = URI.encode_www_form(clean) unless clean.empty?
    end
    uri
  end

  def build_request(method, uri, body)
    request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch,
                       delete: Net::HTTP::Delete, head: Net::HTTP::Head }.fetch(method)
    request = request_class.new(uri)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request['X-API-Key'] = @api_key if @api_key
    # Auto-generate a fresh idempotency key on every mutating request unless
    # the caller already set one in the body (e.g. buy_proxy's
    # idempotency_key param). GETs never send this header.
    request['X-Idempotency-Key'] = SecureRandom.uuid unless get_or_head?(method)
    request.body = JSON.generate(body) if body
    request
  end

  def parse_response(response, status, method)
    raw_body = response.body.to_s
    data =
      if raw_body.empty?
        {}
      else
        begin
          JSON.parse(raw_body, symbolize_names: true)
        rescue JSON::ParserError
          { raw: raw_body }
        end
      end

    return data if status >= 200 && status < 300

    raise_for_status(status, data, method)
  end

  def raise_for_status(status, data, method)
    message = data.is_a?(Hash) ? (data[:message] || data[:error]) : nil
    message = message.is_a?(String) ? message : (message.nil? ? "HTTP #{status}" : message.to_s)
    is_mutating = !get_or_head?(method)

    case status
    when 401
      raise BadApiKeyError.new('Invalid API key. Get one at https://virtualsms.io', status: status, body: data)
    when 402
      raise InsufficientBalanceError.new('Insufficient balance. Top up at https://virtualsms.io', status: status, body: data)
    when 404
      raise NotFoundError.new("Not found: #{message}", status: status, body: data)
    when 429
      raise RateLimitedError.new('Rate limit exceeded. Please slow down requests.', status: status, body: data)
    when 500..599
      # Out-of-stock / no-numbers-available. The backend has no distinct
      # status code for this today (confirmed gap -- see SDK spec "Error
      # model"): a 503 with a body containing "out of stock" / "no numbers"
      # is otherwise indistinguishable from any other 5xx. This SDK sniffs
      # the message body to synthesize this subtype client-side.
      # [UNVERIFIED -- backend enhancement needed: a distinct status/code,
      # e.g. 409, would let SDKs drop this sniff.]
      if message =~ /out of stock|no numbers?|no stock/i
        raise NoNumbersError.new("No numbers currently available: #{message}", status: status, body: data)
      end

      if is_mutating
        raise ServerError.new(
          "VirtualSMS had a server error (#{status}) on a request that may have made a purchase or changed state. " \
          'DO NOT blindly retry: first verify with a read call (list_orders/get_order/list_rentals/etc.) whether it ' \
          "actually succeeded, as you may have been charged. Details: #{message}",
          status: status, body: data, retryable: false
        )
      else
        raise ServerError.new(
          "VirtualSMS server error (#{status}). Safe to retry this read-only request. Details: #{message}",
          status: status, body: data, retryable: true
        )
      end
    else
      raise ApiError.new("API error (#{status}): #{message}", status: status, body: data)
    end
  end

  def session_unavailable?(err)
    return true if err.is_a?(NotFoundError)

    [403, 404, 503].include?(err.status.to_i)
  end

  # ─── Shape normalization helpers ────────────────────────────────────────

  def normalize_order(raw)
    raw ||= {}
    {
      order_id: (raw[:order_id] || raw[:id]).to_s,
      phone_number: raw[:phone_number].to_s,
      service: raw[:service],
      country: raw[:country],
      price: raw[:price],
      created_at: raw[:created_at],
      expires_at: raw[:expires_at],
      status: raw[:status].to_s,
      sms_code: raw[:sms_code],
      sms_text: raw[:sms_text],
      messages: raw[:messages],
      cancel_available_at: raw[:cancel_available_at],
      swap_available_at: raw[:swap_available_at]
    }
  end

  def normalize_list_order(o)
    {
      order_id: (o[:order_id] || o[:id]).to_s,
      phone_number: o[:phone_number].to_s,
      service: (o[:service_id] || o[:service]).to_s,
      country: (o[:country_id] || o[:country]).to_s,
      price: to_f(o[:price_charged] || o[:price]),
      created_at: o[:created_at],
      expires_at: o[:expires_at],
      status: o[:status].to_s,
      sms_code: o[:sms_code],
      sms_text: o[:sms_text]
    }
  end

  def normalize_messages(order)
    msgs = order[:messages]
    return msgs if msgs.is_a?(Array) && !msgs.empty?

    text = order[:sms_text] || order[:sms_code]
    text ? [{ content: text, sender: nil, received_at: nil }] : []
  end

  def extract_code(text)
    m = text.to_s.match(/\b(\d{4,8})\b/)
    m && m[1]
  end

  def precheck_cooldown(available_at, action)
    return nil unless available_at

    available_time = parse_time(available_at)
    return nil unless available_time

    now = Time.now
    return nil if now >= available_time

    wait_seconds = (available_time - now).ceil
    {
      error: 'cooldown_active',
      action: action.to_s,
      message: "#{action == :cancel ? 'Cancel' : 'Swap'} cooldown active. Try again in #{wait_seconds} seconds.",
      retry_at: available_at,
      wait_seconds: wait_seconds
    }
  end

  def catalog_countries(service:)
    raw = http_request(:get, '/catalog/countries', params: { service: service })
    items = raw.is_a?(Array) ? raw : (raw[:countries] || [])
    items.map do |c|
      {
        iso: (c[:id] || c[:iso] || c[:country]).to_s,
        name: (c[:name] || c[:country_name]).to_s,
        price_usd: to_f(c[:price] || c[:our_price] || c[:price_usd]),
        count: (c[:count] || 0).to_i
      }
    end
  end

  def build_proxy_username(login, country_code, target_by, location_code, sticky_index = nil, sticky_minutes = nil)
    username = "#{login}__cr.#{country_code.to_s.downcase}"
    loc = location_code.to_s.strip

    if !loc.empty? && target_by.to_s != 'country'
      case target_by.to_s
      when 'state' then username += ";state.#{loc.downcase}"
      when 'city' then username += ";city.#{loc.downcase}"
      when 'zip' then username += ";zip.#{loc}"
      when 'asn' then username += ";asn.#{loc}"
      end
    end

    username += ";sessid.s#{sticky_index};sessttl.#{sticky_minutes || 10}" if sticky_index

    username
  end

  def build_proxy_endpoint_string(host, port, user, pass, format, protocol)
    case format.to_s
    when 'host:port:user:pass'
      "#{host}:#{port}:#{user}:#{pass}"
    when 'user:pass@host:port'
      "#{user}:#{pass}@#{host}:#{port}"
    when 'curl'
      scheme = protocol.to_s.upcase == 'SOCKS5' ? 'socks5h' : 'http'
      "curl -x \"#{scheme}://#{user}:#{pass}@#{host}:#{port}\" https://api.ipify.org"
    else
      "#{host}:#{port}:#{user}:#{pass}"
    end
  end

  def esc(value)
    URI.encode_www_form_component(value.to_s)
  end

  def to_f(value)
    value.nil? ? 0.0 : value.to_f
  end

  def parse_time(value)
    return nil if value.nil? || value.to_s.empty?

    Time.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
