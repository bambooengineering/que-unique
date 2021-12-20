# frozen_string_literal: true

require "spec_helper"

RSpec.describe ::Que::Unique do
  context "checking the thread locals" do
    before(:each) do
      Que.adapter = Que::Testing::Adapter.new
    end

    after(:each) do
      TestUniqueJob.jobs.clear
      expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq({})
      expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(0)
    end

    it "enqueues as normal with no args" do
      ActiveRecord::Base.transaction do
        3.times { TestUniqueJob.enqueue }
      end
      expect(TestUniqueJob.jobs.count).to eq(1)
    end

    it "has the right thread locals during nested transactions" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", bar: :baz)
        TestUniqueJob.enqueue("qux", bar: :bob)

        expected = {
          { TestUniqueJob => ["foo", { bar: :baz }] }.to_json => true,
          { TestUniqueJob => ["qux", { bar: :bob }] }.to_json => true
        }
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected)
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(1)
        expect(TestUniqueJob.jobs.count).to eq(2)

        expected_inner = {
          { TestUniqueJob => ["foo", { bar: :baz }] }.to_json => true,
          { TestUniqueJob => ["qux", { bar: :bob }] }.to_json => true,
          { TestUniqueJob => ["bip", { bar: :baz }] }.to_json => true
        }

        ActiveRecord::Base.transaction do
          TestUniqueJob.enqueue("foo", bar: :baz) # Should be ignored
          TestUniqueJob.enqueue("bip", bar: :baz) # Should be added
          expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected_inner)
          expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(2)
          expect(TestUniqueJob.jobs.count).to eq(3)
        end

        # Now, check that the inner transaction elements are still enqueued, and the depth has
        # wound back one.
        # ie, the depth and array length are different
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(1)
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected_inner)
        expect(TestUniqueJob.jobs.count).to eq(3)
      end
      expect(TestUniqueJob.jobs.count).to eq(3)
    end

    it "has the right thread locals when a rollback occurs" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", bar: :baz)
        expected_outer = {
          { TestUniqueJob => ["foo", { bar: :baz }] }.to_json => true
        }
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected_outer)
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(1)
        expect(TestUniqueJob.jobs.count).to eq(1)

        expected_inner = {
          { TestUniqueJob => ["foo", { bar: :baz }] }.to_json => true,
          { TestUniqueJob => ["bip", { bar: :baz }] }.to_json => true
        }
        begin
          ActiveRecord::Base.transaction do
            TestUniqueJob.enqueue("foo", bar: :baz) # Should be ignored
            TestUniqueJob.enqueue("bip", bar: :baz) # Should be added

            expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected_inner)
            expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(2)
            expect(TestUniqueJob.jobs.count).to eq(2)

            # Now throw an exception that will cause a rollback.
            raise "Rollback now!"
          end
        rescue
          # At this point, the depth should be back to one, and the enqueued cache should be
          # length 2
          expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL_DEPTH]).to eq(1)
          expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL].keys.count).to eq(2)
          # And carry on...
        end

        # Check that the inner transaction elements *are* enqueued. This may no be what you expect,
        # but it is how ActiveRecord works. http://goo.gl/sa6uz0
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected_inner)
      end
    end

    it "enqueues multiple of the same as 1" do
      ActiveRecord::Base.transaction do
        3.times { TestUniqueJob.enqueue("foo", bar: :baz) }
      end
      expect(TestUniqueJob.jobs.count).to eq(1)
    end

    it "enqueues differently ordered hashes as 1" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", bar: :baz, foo: :qux)
        TestUniqueJob.enqueue("foo", foo: :qux, bar: :baz)
        expected = {
          { TestUniqueJob => ["foo", { bar: :baz, foo: :qux }] }.to_json => true
        }
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected)
      end
      expect(TestUniqueJob.jobs.count).to eq(1)
    end

    it "enqueues different strings as different calls" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", bar: :baz)
        TestUniqueJob.enqueue("qux", bar: :baz)
      end
      expect(TestUniqueJob.jobs.count).to eq(2)
    end

    it "enqueues different hashes as different calls" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", bar: :baz)
        TestUniqueJob.enqueue("foo", qux: :baz)
        TestUniqueJob.enqueue("foo", bar: :qux)
      end
      expect(TestUniqueJob.jobs.count).to eq(3)
    end

    it "enqueues classes as strings" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("Test string")
        expected = {
          { TestUniqueJob => ["Test string"] }.to_json => true
        }
        expect(Thread.current[QUE_UNIQUE_THREAD_LOCAL]).to eq(expected)
      end
      expect(TestUniqueJob.jobs.count).to eq(1)
    end
  end

  context "checking the DB access" do
    before(:each) do
      Que.connection = ActiveRecord
      ActiveRecord::Base.connection.execute("DELETE FROM que_jobs")
      expect(que_job_count).to eq(0)
    end

    def select_jobs
      ActiveRecord::Base.connection.execute("SELECT * FROM que_jobs")
    end

    def que_job_count
      select_jobs.to_a.count
    end

    it "ensures only one of this job gets enqueued for the same args" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("Test string", "urn:banco:1234")
        TestUniqueJob.enqueue("Test string", "urn:banco:1234")
        expect(que_job_count).to eq(1)
      end
      expect(que_job_count).to eq(1)
    end

    it "rollbacks from an error in a transaction" do
      did_error = false
      begin
        ActiveRecord::Base.transaction do
          TestUniqueJob.enqueue("Test string", "urn:banco:1234")
          expect(que_job_count).to eq(1)
          raise "Oh no!"
        end
      rescue
        did_error = true
      end

      expect(did_error).to be true
      expect(que_job_count).to eq(0)
    end

    # This test explicitly checks that QueUnique does not try and do anything "clever" about nested
    # transaction do blocks, and it doesn't try to "unenqueue" any jobs.
    it "does not rollback an inner enqueue from an error in a nested transaction" do
      did_error = false
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("Test string", "urn:banco:1234")
        expect(que_job_count).to eq(1)

        begin
          ActiveRecord::Base.transaction do
            TestUniqueJob.enqueue("Test string", "urn:banco:3456")
            expect(que_job_count).to eq(2)
            raise "Oh no!"
          end
        rescue
          # At this point, although the inner transaction block has been busted out of, no DB
          # rollback has occurred, as we are still in the one single transaction. Thus, the
          # job should still be enqueued.
          did_error = true
        end
      end

      expect(did_error).to be true
      expect(que_job_count).to eq(2)
    end

    it "enqueues and checks for multiple args" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz }, 4, String)
      end
      records_array = select_jobs
      enqueued_args = records_array.first["args"]
      as_array = JSON.parse(enqueued_args)
      expect(as_array).to eq(["foo", { "bar" => "baz" }, 4, "String"])
    end

    class SomeTestClass
      # Used to check class => string conversion
    end

    # By default, to_json converts a Class to '{}'. Various libraries like multi_json and oj
    # cater for this. Que::JSON_MODULE has a json dump method that uses them.
    it "converts Class to a string in the DB" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue(SomeTestClass)
      end
      enqueued_args = select_jobs.first["args"]
      expect(JSON.parse(enqueued_args)).to eq(["SomeTestClass"])
    end

    it "enqueues one of each type of unique job, even if their arguments are the same" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("")
        TestAnotherUniqueJob.enqueue("")
      end
      enqueued = select_jobs.to_a.map { |r| r["job_class"] }
      expect(enqueued).to eq(%w[TestUniqueJob TestAnotherUniqueJob])
    end
  end
end
