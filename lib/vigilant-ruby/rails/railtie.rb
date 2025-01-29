# frozen_string_literal: true

require 'rails/railtie'
require 'vigilant-ruby/logger'
require 'vigilant-ruby/rails/logger'

module Vigilant
  module Rails
    # Railtie for integrating Vigilant with Rails.
    class Railtie < ::Rails::Railtie
      initializer 'vigilant.rails_integration' do
        nil
      end
    end
  end
end
