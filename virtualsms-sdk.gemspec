Gem::Specification.new do |spec|
  spec.name          = 'virtualsms-sdk'
  spec.version       = '1.0.0'
  spec.authors       = ['VirtualSMS']
  spec.email         = 'dev@virtualsms.io'

  spec.summary       = 'VirtualSMS account verification platform: Ruby SDK for SMS verification ' \
                        'with real carrier mobile numbers, not VoIP'
  spec.description   = 'VirtualSMS is an account verification platform that combines real carrier ' \
                        'mobile numbers, matching-country proxies and a private cloud browser into ' \
                        'one connected workflow. This gem is the Ruby SDK for SMS verification: ' \
                        'real physical SIM cards, not VoIP, across WhatsApp, Telegram, Google and ' \
                        '2500+ services in 145+ countries, with 95%+ delivery on real carrier SIMs. ' \
                        'Crypto payments. API compatible with the sms-activate protocol. See ' \
                        'https://virtualsms.io/docs for full platform access.'
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
