# frozen_string_literal: true

require "active_record"

module DbSupport
  class << self
    def setup_db
      testing_db = "que_unique_testing"
      db_config = {
        adapter: "postgresql",
        database: testing_db,
        username: "postgres",
        password: ENV.fetch("DB_PASSWORD", "postgres"),
        host: ENV.fetch("DB_HOST", "127.0.0.1"),
        port: ENV.fetch("DB_PORT", 5432),
        reconnect: true,
      }
      ActiveRecord::Base.establish_connection(db_config.merge(database: "postgres"))

      conn = ActiveRecord::Base.connection
      if conn.execute("SELECT 1 from pg_database WHERE datname='#{testing_db}';").count > 0
        conn.execute("DROP DATABASE #{testing_db}")
      end
      conn.execute("CREATE DATABASE #{testing_db}")

      ActiveRecord::Base.establish_connection(db_config)
      Que.connection = ActiveRecord

      # First migrate Que
      Que.migrate!(version: ::Que::Migrations::CURRENT_VERSION)
    end
  end
end
