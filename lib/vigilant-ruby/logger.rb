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
    # @param passthrough [Boolean] Whether to also print logs to stdout/stderr (optional, defaults to true).
    def initialize(endpoint:, token:, insecure: false, passthrough: true)
      @token = token

      protocol = insecure ? 'http://' : 'https://'
      endpoint = endpoint.sub(%r{^https?://}, '') # remove any existing protocol
      @endpoint = URI.parse("#{protocol}#{endpoint}/api/message")

      @insecure = insecure
      @passthrough = passthrough

      @batch_size     = DEFAULT_BATCH_SIZE
      @flush_interval = DEFAULT_FLUSH_INTERVAL

      @queue = Queue.new
      @mutex = Mutex.new
      @batch = []

      @original_stdout = $stdout
      @original_stderr = $stderr

      @autocapture_enabled = false

      start_dispatcher
    end

    # Logs a debug message.
    def debug(body, attributes = {})
      enqueue_log(DEBUG, body, attributes)
    end

    # Logs an info message.
    def info(body, attributes = {})
      enqueue_log(INFO, body, attributes)
    end

    # Logs a warning message.
    def warn(body, attributes = {})
      enqueue_log(WARNING, body, attributes)
    end

    # Logs an error message.
    def error(body, error = nil, attributes = {})
      if error.nil?
        enqueue_log(ERROR, body, attributes)
      else
        attributes_with_error = { error: error.message, **attributes }
        enqueue_log(ERROR, body, attributes_with_error)
      end
    end

    # Enables stdout/stderr autocapture.
    def autocapture_enable
      return if @autocapture_enabled

      @autocapture_enabled = true
      $stdout = StdoutInterceptor.new(self, @original_stdout)
      $stderr = StderrInterceptor.new(self, @original_stderr)
    end

    # Disables stdout/stderr autocapture.
    def autocapture_disable
      return unless @autocapture_enabled

      @autocapture_enabled = false
      $stdout = @original_stdout
      $stderr = @original_stderr
    end

    # Shuts down the logger, flushing any pending logs.
    def shutdown
      flush_if_needed(force: true)
      @mutex.synchronize { @shutdown = true }
      @dispatcher_thread&.join
    end

    private

    def enqueue_log(level, body, attributes)
      autocaptured = attributes.delete(:_autocapture)

      log_msg = {
        timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%9NZ'),
        body: body.to_s,
        level: level.to_s,
        attributes: attributes.transform_values(&:to_s)
      }

      @queue << log_msg

      return unless @passthrough && !autocaptured

      @original_stdout.puts(body)
    end

    def start_dispatcher
      @shutdown = false
      @dispatcher_thread = Thread.new do
        until @mutex.synchronize { @shutdown }
          flush_if_needed
          sleep @flush_interval
        end
        flush_if_needed(force: true)
      end
    end

    def flush_if_needed(force: false)
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

  # Interceptor for capturing stdout
  class StdoutInterceptor
    def initialize(logger, original)
      @logger   = logger
      @original = original
    end

    def write(message)
      @logger.info(message.strip, _autocapture: true) unless message.strip.empty?
      @original.write(message)
    end

    def puts(*messages)
      messages.each do |m|
        @logger.info(m.to_s.strip, _autocapture: true) unless m.to_s.strip.empty?
      end
      @original.puts(*messages)
    end

    def print(*messages)
      messages.each do |m|
        @logger.info(m.to_s.strip, _autocapture: true) unless m.to_s.strip.empty?
      end
      @original.print(*messages)
    end

    def printf(*args)
      formatted = sprintf(*args)
      @logger.info(formatted.strip, _autocapture: true) unless formatted.strip.empty?
      @original.printf(*args)
    end

    def flush
      @original.flush
    end

    def close
      @original.close
    end

    def tty?
      @original.tty?
    end

    def respond_to_missing?(meth, include_private = false)
      @original.respond_to?(meth, include_private)
    end

    def method_missing(meth, *args, &blk)
      @original.send(meth, *args, &blk)
    end
  end

  # Interceptor for capturing stderr
  class StderrInterceptor
    def initialize(logger, original)
      @logger   = logger
      @original = original
    end

    def write(message)
      @logger.error(message.strip, nil, _autocapture: true) unless message.strip.empty?
      @original.write(message)
    end

    def puts(*messages)
      messages.each do |m|
        @logger.error(m.to_s.strip, nil, _autocapture: true) unless m.to_s.strip.empty?
      end
      @original.puts(*messages)
    end

    def print(*messages)
      messages.each do |m|
        @logger.error(m.to_s.strip, nil, _autocapture: true) unless m.to_s.strip.empty?
      end
      @original.print(*messages)
    end

    def printf(*args)
      formatted = sprintf(*args)
      @logger.error(formatted.strip, nil, _autocapture: true) unless formatted.strip.empty?
      @original.printf(*args)
    end

    def flush
      @original.flush
    end

    def close
      @original.close
    end

    def tty?
      @original.tty?
    end

    def respond_to_missing?(meth, include_private = false)
      @original.respond_to?(meth, include_private)
    end

    def method_missing(meth, *args, &blk)
      @original.send(meth, *args, &blk)
    end
  end
end
