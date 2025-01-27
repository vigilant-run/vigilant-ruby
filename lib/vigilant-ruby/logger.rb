# frozen_string_literal: true

require 'net/http'
require 'json'
require 'time'
require 'vigilant-ruby/version'

module Vigilant
  DEBUG = 'DEBUG'
  INFO = 'INFO'
  WARNING = 'WARNING'
  ERROR = 'ERROR'

  DEFAULT_BATCH_SIZE = 10
  DEFAULT_FLUSH_INTERVAL = 5

  # A thread-safe logger that batches logs and sends them to Vigilant asynchronously
  class Logger
    # Initialize a Vigilant::Logger instance.
    #
    # @param endpoint [String] The base endpoint for the Vigilant API (e.g. "ingress.vigilant.run").
    # @param token [String] The authentication token for the Vigilant API.
    # @param insecure [Boolean] Whether to use HTTP instead of HTTPS (optional, defaults to false).
    def initialize(endpoint:, token:, insecure: false)
      @token = token
      protocol = insecure ? 'http://' : 'https://'
      endpoint = endpoint.sub(%r{^https?://}, '') # Remove any existing protocol
      @endpoint = URI.parse("#{protocol}#{endpoint}/api/message")
      @insecure = insecure

      @batch_size = DEFAULT_BATCH_SIZE
      @flush_interval = DEFAULT_FLUSH_INTERVAL

      @queue = Queue.new
      @mutex = Mutex.new
      @batch = []

      start_dispatcher
    end

    # Logs a TRACE message.
    #
    # @param body [String] The main text of the trace message.
    # @param attributes [Hash] Additional attributes for the log (optional).
    def trace(body, attributes = {})
      enqueue_log(TRACE, body, attributes)
    end

    # Logs a DEBUG message.
    #
    # @param body [String] The main text of the debug message.
    # @param attributes [Hash] Additional attributes for the log (optional).
    def debug(body, attributes = {})
      enqueue_log(DEBUG, body, attributes)
    end

    # Logs an INFO message.
    #
    # @param body [String] The main text of the log message.
    # @param attributes [Hash] Additional attributes for the log (optional).
    def info(body, attributes = {})
      enqueue_log(INFO, body, attributes)
    end

    # Logs a WARNING message.
    #
    # @param body [String] The main text of the warning message.
    # @param attributes [Hash] Additional attributes for the log (optional).
    def warn(body, attributes = {})
      enqueue_log(WARNING, body, attributes)
    end

    # Logs an ERROR message.
    #
    # @param body [String] The main text of the error message.
    # @param error [Exception] The error object.
    # @param attributes [Hash] Additional attributes for the log (optional).
    def error(body, error = nil, attributes = {})
      if error.nil?
        enqueue_log(ERROR, body, attributes)
      else
        attributes_with_error = { error: error.message, **attributes }
        enqueue_log(ERROR, body, attributes_with_error)
      end
    end

    def shutdown
      flush_if_needed(true)

      @mutex.synchronize do
        @shutdown = true
      end

      @dispatcher_thread&.join
    end

    private

    def enqueue_log(level, body, attributes)
      string_attributes = attributes.transform_values(&:to_s)
      log_msg = {
        timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%9NZ'),
        body: body.to_s,
        level: level.to_s,
        attributes: string_attributes
      }
      @queue << log_msg
    end

    def start_dispatcher
      @shutdown = false
      @dispatcher_thread = Thread.new do
        until @mutex.synchronize { @shutdown }
          flush_if_needed
          sleep @flush_interval
        end
        flush_if_needed(true)
      end
    end

    def flush_if_needed(force = false)
      until @queue.empty?
        msg = @queue.pop
        @mutex.synchronize { @batch << msg }
      end

      @mutex.synchronize do
        flush! if force || @batch.size >= @batch_size || !@batch.empty?
      end
    end

    def flush!
      return if @batch.empty?

      logs_to_send = @batch.dup
      @batch.clear

      request_body = {
        token: @token,
        type: 'logs',
        logs: logs_to_send
      }

      post_logs(request_body)
    rescue StandardError => e
      warn("Failed to send logs: #{e.message}")
    end

    def post_logs(batch_data)
      http = Net::HTTP.new(@endpoint.host, @endpoint.port)
      http.use_ssl = !@insecure

      request = Net::HTTP::Post.new(@endpoint)
      request['Content-Type'] = 'application/json'
      request.body = JSON.dump(batch_data)

      http.request(request)
    end
  end
end
