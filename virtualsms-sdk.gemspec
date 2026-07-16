Gem::Specification.new do |spec|
  spec.name          = 'virtualsms-sdk'
  spec.version       = '1.0.0'
  spec.authors       = ['VirtualSMS']
  spec.email         = 'dev@virtualsms.io'

  spec.summary       = 'Ruby SDK for VirtualSMS SMS verification — real carrier numbers, not VoIP'
  spec.description   = 'Ruby SDK for VirtualSMS account verification — real carrier mobile numbers, ' \
                        'not VoIP. Supports WhatsApp, Telegram, Google and 700+ services. ' \
                        'Near-100% delivery rates. Crypto payments. API compatible with the ' \
                        'sms-activate protocol. Part of the VirtualSMS platform (numbers, proxies, ' \
                        'cloud browser) — see https://virtualsms.io/docs for full platform access.'
  spec.homepage      = 'https://virtualsms.io'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata = {
    'homepage_uri'      => 'https://virtualsms.io',
    'source_code_uri'   => 'https://github.com/virtualsms-io/ruby-sdk',
    'documentation_uri' => 'https://virtualsms.io/api',
    'changelog_uri'     => 'https://github.com/virtualsms-io/ruby-sdk/blob/main/CHANGELOG.md',
    'bug_tracker_uri'   => 'https://github.com/virtualsms-io/ruby-sdk/issues'
  }

  spec.files         = Dir['lib/**/*.rb', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_dependency 'net-http', '~> 0.3'
end
