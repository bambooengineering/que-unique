# frozen_string_literal: true

module Que
  module Unique
    THREAD_LOCAL_KEY = :que_unique_thread_local
    THREAD_LOCAL_DEPTH_KEY = :que_unique_thread_local_depth
  end
end
