# frozen_string_literal: true

require_relative "unique/version"
require "active_record"
require "que"

QUE_UNIQUE_THREAD_LOCAL = :que_unique_thread_local
QUE_UNIQUE_THREAD_LOCAL_DEPTH = :que_unique_thread_local_depth

# This block adds the wrapping around all transactions to either start the thread local, or
# increment it so we know how deep we are in the transaction nesting.
module QueUniqueTransaction
  module ClassMethods
    def self.extended(base)
      base.class_eval do
        class << self
          alias_method :transaction_without_unique_que, :transaction
          alias_method :transaction, :transaction_with_unique_que
        end
      end
    end

    def transaction_with_unique_que(*args)
      start_que_unique_handled_transaction
      transaction_without_unique_que(*args) do
        yield
      end
    ensure
      end_que_unique_handled_transaction
    end

    private

    def start_que_unique_handled_transaction
      # Set the defaults for the thread local, then delegate to the real block.
      Thread.current[QUE_UNIQUE_THREAD_LOCAL] ||= {}
      # We keep track of the nested depth, so we know when to clear the array
      Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH] ||= 0
      # Now we know we are initialised, increment the transaction counter
      Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH] += 1
    end

    def end_que_unique_handled_transaction
      # Note the depth. When we are back to zero, assume all the Que jobs have been committed,
      # so reset the hash.
      Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH] -= 1
      if Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH] == 0
        Thread.current[QUE_UNIQUE_THREAD_LOCAL] = {}
      end
    end
  end
end

ActiveRecord::Base.send(:extend, QueUniqueTransaction::ClassMethods)

# This block wraps the enqueue method of Que::Unique jobs. For each json of args, we store in a hash
module Que
  module Unique
    extend ActiveSupport::Concern
    included do
      singleton_class.class_eval do
        def enqueue_before_unique(*args)
          thread_local_hash = Thread.current[QUE_UNIQUE_THREAD_LOCAL]
          unless thread_local_hash
            raise "UniqueQueJob #{self} being scheduled outside a transaction"
          end

          # Once the args are canonicalised, we convert it to a JSON string to match against.
          canonicalised_args = args.map { |arg| canonicalise_que_unique_arg(arg) }
          args_key = { self => canonicalised_args }.to_json
          # If this is already known then don't enqueue it again. Otherwise, add it to the last
          # element of the array.
          if thread_local_hash.key?(args_key)
            ::Rails.logger.debug "Que::Unique - #{self} - Already scheduled: #{args_key}"
          else
            ::Rails.logger.debug "Que::Unique - #{self} - Enqueuing #{args_key}"
            thread_local_hash[args_key] = true
            enqueue_after_unique(*canonicalised_args)
          end
        end

        alias_method :enqueue_after_unique, :enqueue
        alias_method :enqueue, :enqueue_before_unique

        private

        def canonicalise_que_unique_arg(value)
          case
          when value.is_a?(Class)
            # When we try to enqueue a Class as an arg (very common), to_json chokes.
            # We must convert it to a string manually.
            value.to_s
          when value.is_a?(Hash)
            # Hashes are sorted by insertion order by default, so instead, create a new hash sorted
            # by key/value pairs.
            value.sort.to_h
          else
            value
          end
        end
      end
    end
  end
end
