# frozen_string_literal: true

require "active_record"
require_relative "constants"

# This block adds the wrapping around all transactions to either start the thread local, or
# increment it so we know how deep we are in the transaction nesting.
module Que
  module Unique
    module TransactionClassMethods
      def transaction_with_unique_que(...)
        start_que_unique_handled_transaction
        transaction_without_unique_que(...)
      ensure
        end_que_unique_handled_transaction
      end

      class << self
        def extended(base)
          base.class_eval do
            class << self
              alias_method :transaction_without_unique_que, :transaction
              alias_method :transaction, :transaction_with_unique_que
            end
          end
        end
      end

      private

      def start_que_unique_handled_transaction
        # Set the defaults for the thread local, then delegate to the real block.
        Thread.current[Que::Unique::THREAD_LOCAL_KEY] ||= {}
        # We keep track of the nested depth, so we know when to clear the array
        Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY] ||= 0
        # Now we know we are initialised, increment the transaction counter
        Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY] += 1
      end

      def end_que_unique_handled_transaction
        # Note the depth. When we are back to zero, assume all the Que jobs have been committed,
        # so reset the hash.
        Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY] -= 1
        return unless Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY].zero?

        Thread.current[Que::Unique::THREAD_LOCAL_KEY] = {}
      end
    end
  end
end

ActiveRecord::Base.extend Que::Unique::TransactionClassMethods
