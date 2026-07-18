require_relative 'lib/virtualsms/version'

Gem::Specification.new do |spec|
  spec.name          = 'virtualsms-sdk'
  spec.version       = VirtualSMS::VERSION
  spec.authors       = ['VirtualSMS']
  spec.email         = 'dev@virtualsms.io'

  spec.summary       = 'Native Ruby client for the VirtualSMS REST API v1: SMS verification, ' \
                        'number rentals and proxies behind one API key.'
  spec.description   = 'VirtualSMS is an account verification platform for individuals, developers ' \
                        'and AI agents. It combines one-time SMS verification with real carrier ' \
                        'mobile numbers (not VoIP), dedicated number rentals, matching-country ' \
                        'proxies and private cloud browser sessions behind one REST API, one MCP ' \
                        'server, and one prepaid balance. This gem is a native client for the ' \
                        '/api/v1 REST surface: services, countries, pricing, orders, rentals, ' \
                        'proxies, account, browser sessions and webhooks. See https://virtualsms.io/docs ' \
                        'for the full API reference.'
  spec.homepage      = 'https://virtualsms.io'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata = {
    'homepage_uri'      => 'https://virtualsms.io',
    'source_code_uri'   => 'https://github.com/virtualsms-io/ruby-sdk',
    'documentation_uri' => 'https://virtualsms.io/docs',
    'changelog_uri'     => 'https://github.com/virtualsms-io/ruby-sdk/blob/main/CHANGELOG.md',
    'bug_tracker_uri'   => 'https://github.com/virtualsms-io/ruby-sdk/issues',
    'rubygems_mfa_required' => 'true'
  }

  spec.files         = Dir['lib/**/*.rb', 'README.md', 'LICENSE', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  # No runtime dependencies: net/http, uri, json, securerandom and time are
  # all Ruby standard library, not gems. v1.0.0 declared a bogus `net-http`
  # gem dependency (net/http has never been a separate gem); dropped in
  # v2.0.0.

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end
