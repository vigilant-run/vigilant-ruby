# frozen_string_literal: true

require 'vigilant-ruby/version'
require 'vigilant-ruby/logger'

# Vigilant is a logging service that provides structured logging capabilities
# with asynchronous batch processing and thread-safe operations.
module Vigilant
  class Error < StandardError; end

  # Configuration for the Vigilant logging service.
  class Configuration
    attr_accessor :endpoint, :token, :insecure

    def initialize
      @endpoint = 'ingress.vigilant.run'
      @insecure = false
      @token = 'tk_1234567890'
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def logger
      @logger ||= Vigilant::Logger.new(
        endpoint: configuration.endpoint,
        insecure: configuration.insecure,
        token: configuration.token
      )
    end
  end
end
