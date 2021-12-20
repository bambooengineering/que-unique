# frozen_string_literal: true

class TestAnotherUniqueJob < Que::Job
  include ::Que::Unique

  def run(some_string, some_hash)
    call_the_args(some_string, some_hash)
  end
end
