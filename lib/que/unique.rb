# frozen_string_literal: true

require "que"
require_relative "unique/version"
require_relative "unique/constants"
require_relative "unique/transaction_class_methods"

# This block wraps the enqueue method of Que::Unique jobs.
# For each json of args, we store in a hash.
module Que
  module Unique
    extend ActiveSupport::Concern

    included do
      singleton_class.class_eval do
        def enqueue_before_unique(*args)
          thread_local_hash = Thread.current[Que::Unique::THREAD_LOCAL_KEY]
          unless thread_local_hash
            raise "UniqueQueJob #{self} being scheduled outside a transaction"
          end

          # Once the args are canonicalised, we convert it to a JSON string to match against.
          canonicalised_args = args.map { |arg| Que::Unique.canonicalise_que_unique_arg(arg) }
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
      end
    end

    class << self
      def canonicalise_que_unique_arg(value)
        case value
        when Class
          # When we try to enqueue a Class as an arg (very common), to_json chokes.
          # We must convert it to a string manually.
          value.to_s
        when Hash
          # Hashes are sorted by insertion order by default, so instead, create a new
          # hash sorted by key/value pairs.
          value.sort.to_h
        else
          value
        end
      end
    end
  end
end
