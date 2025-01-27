# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'vigilant-ruby'
  spec.version       = '0.0.2'
  spec.authors       = ['Vigilant']
  spec.email         = ['izak@vigilant.run']

  spec.summary       = 'Ruby SDK for Vigilant'
  spec.description   = 'Official Ruby SDK for interacting with the Vigilant API'
  spec.homepage      = 'https://vigilant.run'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['homepage_uri'] = 'https://vigilant.run'
  spec.metadata['source_code_uri'] = 'https://github.com/vigilant-run/vigilant-ruby'
  spec.metadata['changelog_uri'] = 'https://vigilant.run/changelog'

  spec.files = Dir.glob('{lib,sig}/**/*') + %w[README.md]
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'json', '~> 2.0'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rbs', '~> 3.1'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'yard', '~> 0.9'
end
