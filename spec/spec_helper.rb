# frozen_string_literal: true

require "bundler/setup"
require "que/unique"
require "combustion"
require "pry-byebug"
require "database_cleaner"

Dir["#{__dir__}/../spec/support/**/*.rb"].sort.each { |f| require f }

Combustion.schema_format = :sql
Combustion.initialize! :active_record, :action_controller

# We have to apply special settings and a patch for que 0.x
if Gem.loaded_specs["que"].version < Gem::Version.new("1.0")
  Que.mode = :off

  # https://github.com/que-rb/que/issues/247#issuecomment-595258236
  Que::Adapters::Base::CAST_PROCS[1184] = lambda do |value|
    case value
    when Time then value
    when String then Time.parse(value)
    else raise "Unexpected time class: #{value.class} (#{value.inspect})"
    end
  end
end

# In Rails 5 this class is automatically generated in any new application. Test models should
# extend from it to prevent rubocop warnings.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

# rubocop:disable Lint/EmptyClass
class SomeTestClass
  # Used to check class => string conversion
end
# rubocop:enable Lint/EmptyClass

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.before(:suite) do
    DbSupport.setup_db
  end
  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
