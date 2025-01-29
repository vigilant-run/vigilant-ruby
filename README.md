# Vigilant Ruby SDK

This is the Ruby SDK for Vigilant (https://vigilant.run).

## Installation

```bash
bundle add vigilant-ruby
```

## Logging Usage (Rails)

```ruby
# In config/application.rb
require 'vigilant-ruby'

module YourApp
  class Application < Rails::Application
    config.logger = Vigilant::Rails::Logger.new(token: 'tk_1234567890', name: 'test-app')
    config.log_level = :debug
  end
end
```

## Logging Usage (Standard)

```ruby
require 'vigilant-ruby'

# Initialize the logger
logger = Vigilant::Logger.new(
  name: 'test-app',
  token: 'tk_1234567890',
)

# Basic logging
logger.info('User logged in')
logger.warn('Rate limit approaching')
logger.error('Database connection failed')
logger.debug('Processing request')

# Logging with attributes
logger.info('User logged in', { user_id: 123, ip_address: '192.168.1.1' })

# Shutdown the logger
logger.shutdown
```

## Logging Usage (Autocapture)

```ruby
require 'vigilant-ruby'

# Initialize the logger
logger = Vigilant::Logger.new(
  name: 'test-app',
  token: 'tk_1234567890',
)

# Enable autocapture
logger.autocapture_enable

# Log with autocapture
puts 'A print statement'

# Log without autocapture
logger.info('A regular log')

# Shutdown the logger
logger.shutdown
```
