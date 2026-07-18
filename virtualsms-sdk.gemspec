require_relative 'lib/virtualsms/version'

Gem::Specification.new do |spec|
  spec.name          = 'virtualsms-sdk'
  spec.version       = VirtualSMS::VERSION
  spec.authors       = ['VirtualSMS']
  spec.email         = 'dev@virtualsms.io'

  spec.summary       = 'Official Ruby SDK for the VirtualSMS account verification API.'
  spec.description   = 'VirtualSMS is an account verification platform for individuals, developers, ' \
                        'and AI agents. It combines one-time SMS verification, dedicated number ' \
                        'rentals, matching-country proxies, and private cloud browser sessions ' \
                        'behind one API, one MCP server, and one prepaid balance. This gem is the ' \
                        'official Ruby client for the VirtualSMS REST API, backed by real ' \
                        'carrier-issued mobile numbers (real physical SIM cards, not VoIP) across ' \
                        '2500+ services in 145+ countries.'
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
