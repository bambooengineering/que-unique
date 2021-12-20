# frozen_string_literal: true

require "que/unique"
require "que/testing"
require "combustion"
require "pry-byebug"

Combustion.schema_format = :sql
Combustion.initialize! :active_record, :action_controller

Que.mode = :off

# In Rails 5 this class is automatically generated in any new application. Test models should
# extend from it to prevent rubocop warnings.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class SomeTestClass
  # Used to check class => string conversion
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
