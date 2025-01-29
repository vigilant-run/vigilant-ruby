# frozen_string_literal: true

require 'active_support/logger'
require 'json'

module Vigilant
  module Rails
    # A wrapper that delegates Rails-style logging calls to Vigilant::Logger
    class Logger < ::ActiveSupport::Logger
      include ::ActiveSupport::LoggerThreadSafeLevel if defined?(::ActiveSupport::LoggerThreadSafeLevel)

      if defined?(::ActiveSupport::LoggerSilence)
        include ::ActiveSupport::LoggerSilence
      elsif defined?(::LoggerSilence)
        include ::LoggerSilence
      end

      SEVERITY_MAP = {
        ::Logger::DEBUG => Vigilant::DEBUG,
        ::Logger::INFO => Vigilant::INFO,
        ::Logger::WARN => Vigilant::WARNING,
        ::Logger::ERROR => Vigilant::ERROR,
        ::Logger::FATAL => Vigilant::ERROR,
        ::Logger::UNKNOWN => Vigilant::ERROR
      }.freeze

      def initialize(name: Vigilant.configuration.name,
                     endpoint: Vigilant.configuration.endpoint,
                     token: Vigilant.configuration.token,
                     insecure: Vigilant.configuration.insecure,
                     passthrough: Vigilant.configuration.passthrough)
        super(nil)

        @vigilant_logger = Vigilant::Logger.new(
          endpoint: endpoint,
          token: token,
          name: name,
          insecure: insecure,
          passthrough: passthrough
        )

        at_exit { close }

        self.level = ::Logger::DEBUG
        @tags = []
        @extra_loggers = []
      end

      def kind_of?(klass)
        return true if defined?(::ActiveSupport::BroadcastLogger) && klass == ::ActiveSupport::BroadcastLogger

        super(klass)
      end
      alias is_a? kind_of?

      def broadcasts
        [self] + @extra_loggers
      end

      def broadcast_to(*io_devices_and_loggers)
        io_devices_and_loggers.each do |io_device_or_logger|
          extra_logger =
            if io_device_or_logger.is_a?(::Logger)
              io_device_or_logger
            else
              ::ActiveSupport::Logger.new(io_device_or_logger)
            end
          @extra_loggers << extra_logger
        end
      end

      def stop_broadcasting_to(io_device_or_logger)
        if io_device_or_logger.is_a?(::Logger)
          @extra_loggers.delete(io_device_or_logger)
        else
          @extra_loggers.reject! do |logger|
            defined?(::ActiveSupport::Logger) &&
              ::ActiveSupport::Logger.logger_outputs_to?(logger, io_device_or_logger)
          end
        end
      end

      def debug(progname = nil, &block)
        add(::Logger::DEBUG, block, progname)
      end

      def info(progname = nil, &block)
        add(::Logger::INFO, block, progname)
      end

      def warn(progname = nil, &block)
        add(::Logger::WARN, block, progname)
      end

      def error(progname = nil, &block)
        add(::Logger::ERROR, block, progname)
      end

      def fatal(progname = nil, &block)
        add(::Logger::FATAL, block, progname)
      end

      def unknown(progname = nil, &block)
        add(::Logger::UNKNOWN, block, progname)
      end

      def add(severity, message_or_block = nil, progname = nil)
        return true if severity < level

        msg =
          if message_or_block.respond_to?(:call)
            message_or_block.call.to_s
          else
            (message_or_block || progname).to_s
          end.strip

        vigilant_severity = SEVERITY_MAP.fetch(severity, Vigilant::ERROR)
        log_to_vigilant(vigilant_severity, msg)

        @extra_loggers.each { |logger| logger.add(severity, msg, progname) }
        true
      end

      def tagged(*tags)
        push_tags(*tags)
        yield self
      ensure
        pop_tags(tags.size)
      end

      def push_tags(*tags)
        @tags.concat(tags)
      end

      def pop_tags(amount = 1)
        @tags.pop(amount)
      end

      def current_tags
        @tags
      end

      def silence(temporary_level = ::Logger::ERROR)
        old_level = level
        self.level = temporary_level
        yield self
      ensure
        self.level = old_level
      end

      def flush
        @vigilant_logger.flush if @vigilant_logger.respond_to?(:flush)
      rescue StandardError
        nil
      end

      def reopen(_device = nil)
        nil
      end

      def close
        @vigilant_logger.shutdown if @vigilant_logger.respond_to?(:shutdown)
      end

      def datetime_format=(_format)
        nil
      end

      def datetime_format
        nil
      end

      attr_accessor :formatter

      private

      def log_to_vigilant(severity, message)
        formatted_message, attributes = format_message(message)
        case severity
        when Vigilant::DEBUG
          @vigilant_logger.debug(formatted_message, attributes)
        when Vigilant::INFO
          @vigilant_logger.info(formatted_message, attributes)
        when Vigilant::WARNING
          @vigilant_logger.warn(formatted_message, attributes)
        when Vigilant::ERROR
          @vigilant_logger.error(formatted_message, nil, attributes)
        end
      end

      def format_message(message)
        formatted_message = format_tags(message)
        attributes = {}

        begin
          attributes = format_json_attributes(message) if message.start_with?('{') && message.end_with?('}')
        rescue JSON::ParserError
          nil
        end

        begin
          attributes = format_key_value_attributes(message) if message.match?(/^[\w\-.]+=/)
        rescue StandardError
          nil
        end

        [formatted_message, attributes]
      end

      def format_json_attributes(message)
        json_data = JSON.parse(message)
        attributes = json_data['attributes'] ||= {}

        json_data.each do |key, value|
          attributes[key] = value
          json_data.delete(key)
        end

        attributes['tags'] = @tags
        attributes
      end

      def format_key_value_attributes(message)
        attributes = {}
        message.split(' ').each do |pair|
          key, value = pair.split('=', 2)
          value = case value
                  when /^\d+$/
                    value.to_i
                  when /^\d*\.\d+$/
                    value.to_f
                  else
                    value
                  end
          attributes[key] = value
        end

        attributes['tags'] = @tags
        attributes
      end

      def format_tags(message)
        tag_prefix = @tags.map { |t| "[#{t}] " }.join
        "#{tag_prefix}#{message}"
      end
    end
  end
end
