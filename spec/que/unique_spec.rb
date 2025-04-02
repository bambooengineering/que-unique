# frozen_string_literal: true

require "spec_helper"

RSpec.describe Que::Unique do
  before(:each) do
    Que.connection = ActiveRecord
    ActiveRecord::Base.connection.execute("DELETE FROM que_jobs")
    expect(que_job_count).to eq(0)
  end

  # :reek:UtilityFunction
  def select_jobs
    ActiveRecord::Base.connection.execute("SELECT * FROM que_jobs")
  end

  def que_job_count
    select_jobs.to_a.count
  end

  def que_version
    # The constant holding Que's version was renamed in Que 1
    Gem::Version.new(defined?(::Que::Version) ? ::Que::Version : ::Que::VERSION)
  end

  def run_at_kwargs(run_at)
    job_options = { run_at: run_at }

    # Que 1.2. introduced a separate job_options kwarg
    return job_options if que_version < Gem::Version.new("1.2")

    { job_options: job_options }
  end

  context "when checking the thread locals" do
    after(:each) do
      expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq({})
      expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(0)
    end

    it "enqueues as normal with no args" do
      ActiveRecord::Base.transaction do
        3.times { TestUniqueJob.enqueue }
      end
      expect(que_job_count).to eq(1)
    end

    it "has the right thread locals during nested transactions" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg)
        TestUniqueJob.enqueue("qux", { bar: :bob }, my: :kwarg)

        expected = {
          { TestUniqueJob => [["foo", { bar: :baz }], { my: :kwarg }] }.to_json => true,
          { TestUniqueJob => [["qux", { bar: :bob }], { my: :kwarg }] }.to_json => true,
        }
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected)
        expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(1)
        expect(que_job_count).to eq(2)

        expected_inner = {
          { TestUniqueJob => [["foo", { bar: :baz }], { my: :kwarg }] }.to_json => true,
          { TestUniqueJob => [["qux", { bar: :bob }], { my: :kwarg }] }.to_json => true,
          { TestUniqueJob => [["bip", { bar: :baz }], { my: :kwarg }] }.to_json => true,
        }

        ActiveRecord::Base.transaction do
          TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg) # Should be ignored
          TestUniqueJob.enqueue("bip", { bar: :baz }, my: :kwarg) # Should be added
          expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected_inner)
          expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(2)
          expect(que_job_count).to eq(3)
        end

        # Now, check that the inner transaction elements are still enqueued, and the depth has
        # wound back one.
        # ie, the depth and array length are different
        expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(1)
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected_inner)
        expect(que_job_count).to eq(3)
      end
      expect(que_job_count).to eq(3)
    end

    it "has the right thread locals when a rollback occurs" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg)
        expected_outer = {
          { TestUniqueJob => [["foo", { bar: :baz }], { my: :kwarg }] }.to_json => true,
        }
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected_outer)
        expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(1)
        expect(que_job_count).to eq(1)

        expected_inner = {
          { TestUniqueJob => [["foo", { bar: :baz }], { my: :kwarg }] }.to_json => true,
          { TestUniqueJob => [["bip", { bar: :baz }], { my: :kwarg }] }.to_json => true,
        }

        expect do
          ActiveRecord::Base.transaction do
            TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg) # Should be ignored
            TestUniqueJob.enqueue("bip", { bar: :baz }, my: :kwarg) # Should be added

            expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected_inner)
            expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(2)
            expect(que_job_count).to eq(2)

            # Now throw an exception that will cause a rollback.
            raise "Rollback now!"
          end
        end.to raise_error("Rollback now!") do
          # At this point, the depth should be back to one, and the enqueued cache should be
          # length 2
          expect(Thread.current[Que::Unique::THREAD_LOCAL_DEPTH_KEY]).to eq(1)
          expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY].keys.count).to eq(2)
          # And carry on...
        end

        # Check that the inner transaction elements *are* enqueued. This may no be what you expect,
        # but it is how ActiveRecord works. http://goo.gl/sa6uz0
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected_inner)
      end
    end

    it "enqueues multiple of the same as 1" do
      ActiveRecord::Base.transaction do
        3.times { TestUniqueJob.enqueue("foo", { bar: :baz }) }
      end
      expect(que_job_count).to eq(1)
    end

    it "enqueues differently ordered hashes as 1" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz, foo: :qux }, my: :kwarg, another: :kwarg)
        TestUniqueJob.enqueue("foo", { foo: :qux, bar: :baz }, another: :kwarg, my: :kwarg)
        expected = {
          {
            TestUniqueJob => [["foo", { bar: :baz, foo: :qux }], { another: :kwarg, my: :kwarg }]
          }.to_json => true,
        }
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected)
      end
      expect(que_job_count).to eq(1)
    end

    it "enqueues jobs with the same args that run_at different times as different jobs" do
      ActiveRecord::Base.transaction do
        run_at = Time.current + 1.hour

        TestUniqueJob.enqueue("foo", { foo: :qux, bar: :baz }, **run_at_kwargs(run_at), my: :kwarg)
        TestUniqueJob.enqueue("foo", { foo: :qux, bar: :baz }, my: :kwarg, **run_at_kwargs(run_at + 5.minutes))
      end

      run_ats = select_jobs.to_a.map { |h| h.fetch("run_at") }
      expect(run_ats.size).to eq(2)
      expect(run_ats.uniq.size).to eq(2)
    end

    it "enqueues different strings as different calls" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg)
        TestUniqueJob.enqueue("qux", { bar: :baz }, my: :kwarg)
      end
      expect(que_job_count).to eq(2)
    end

    it "enqueues different hashes as different calls" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("foo", { bar: :baz }, my: :kwarg)
        TestUniqueJob.enqueue("foo", { qux: :baz }, my: :kwarg)
        TestUniqueJob.enqueue("foo", { bar: :qux }, my: :kwarg)
      end
      expect(que_job_count).to eq(3)
    end

    it "enqueues classes as strings" do
      ActiveRecord::Base.transaction do
        TestUniqueJob.enqueue("Test string")
        expected = {
          { TestUniqueJob => [["Test string"], {}] }.to_json => true,
        }
        expect(Thread.current[Que::Unique::THREAD_LOCAL_KEY]).to eq(expected)
      end
      expect(que_job_count).to eq(1)
    end
  end

  context "when checking the DB access" do
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
      expect do
        ActiveRecord::Base.transaction do
          TestUniqueJob.enqueue("Test string", "urn:banco:1234")
          expect(que_job_count).to eq(1)
          raise "Oh no!"
        end
      end.to raise_error("Oh no!") do
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

        expect do
          ActiveRecord::Base.transaction do
            TestUniqueJob.enqueue("Test string", "urn:banco:3456")
            expect(que_job_count).to eq(2)
            raise "Oh no!"
          end
        end.to raise_error("Oh no!") do
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
