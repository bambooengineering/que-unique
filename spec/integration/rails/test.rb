# frozen_string_literal: true

require "active_record"
require "rails"
require "que"
require "que/unique"

# Set up database connection
ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  host: "localhost",
  port: "5432",
  username: "postgres",
  password: "postgres",
  database: "postgres"
)
Que.connection = ActiveRecord

if defined?(Que::Version) && Que::Version =~ /^0\./
    # See https://github.com/que-rb/que/issues/247#issuecomment-595258236
    Que::Adapters::Base::CAST_PROCS[1184] = lambda do |value|
      case value
      when Time then value
      when String then Time.parse(value)
      else raise "Unexpected time class: #{value.class} (#{value.inspect})"
      end
    end
end

class SomeJob < Que::Job
  include Que::Unique

  def run
    puts "Running job!"
  end
end

# Define a model class
class User < ActiveRecord::Base
  after_save :queue_job

  def queue_job
    SomeJob.enqueue
  end
end

ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users")

# Create a table for the model
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :name
  end
end

Rails.logger = Logger.new($stdout)

Que.migrate!(version: Que::Migrations::CURRENT_VERSION)

def expect_job_count(expected_count)
  actual_count = ActiveRecord::Base.connection.execute(
    "SELECT count(*) FROM que_jobs WHERE job_class = 'SomeJob'"
  ).to_a.first.fetch("count")

  if actual_count != expected_count
    raise "Expected exactly #{expected_count} jobs but got #{actual_count}"
  end
end

begin
  # Outside of an explicit transaction, but Rails still creates one internally (with a sligthly
  # different code path that we want to ensure is tested)
  User.new(name: "Jane Doe").save!

  expect_job_count(1)

  User.transaction do
    user = User.new(name: "John Doe")
    # Trigger the after_save callback twice which would (without Que-unique) enqueue two jobs
    user.save!
    user.save!

    expect_job_count(2) # Not 3 (if the two saves both enqueued a job)
  end
ensure
  # Always remove Que as the next test run using the same DB may be for an earlier version that
  # does not know how to migrate down from a later version
  Que.migrate!(version: 0)
end
