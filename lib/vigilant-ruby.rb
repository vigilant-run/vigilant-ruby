# frozen_string_literal: true

require 'vigilant-ruby/version'
require 'vigilant-ruby/logger'
require 'vigilant-ruby/rails/railtie' if defined?(Rails)

# Vigilant is a logging library for the Vigilant platform.
module Vigilant
  class Error < StandardError; end

  # Configuration for the Vigilant logging service.
  class Configuration
    attr_accessor :name, :token, :endpoint, :insecure, :passthrough

    def initialize
      @name = 'test-app'
      @token = 'tk_1234567890'
      @endpoint = 'ingress.vigilant.run'
      @insecure = false
      @passthrough = false
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
        name: configuration.name,
        token: configuration.token,
        endpoint: configuration.endpoint,
        insecure: configuration.insecure,
        passthrough: configuration.passthrough
      )
    end
  end
end
