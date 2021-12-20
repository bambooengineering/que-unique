# Que::Unique

`Que::Unique` is a gem that ensures that identical que jobs are not scheduled multiple times during a
transaction block. If the same job with the same args is detected, it will be coalesced into one.
A typical use case would be modifying a customer at various points during
a code route, and wanting to index it once in elasticsearch afterwards.

Use:

```ruby
# Add to Gemfile
gem 'que-unique'

# Add the `include` to your job
class SomeUniqueJob < Que::Job
 include Que::Unique
end
```

Now, when in a transaction, only one of any set of args (as json'd) will be enqueued.

## Examples

Without que-unique:

```ruby
IndexCustomer.enqueue(3)
... business logic
IndexCustomer.enqueue(3)
... business logic
IndexCustomer.enqueue(3)

=> Results in 3 identical index jobs
```

With que-unique:

```ruby
IndexCustomer.enqueue(3)
... business logic
IndexCustomer.enqueue(3)
... business logic
IndexCustomer.enqueue(3)

=> Results in 1 index job
```

With que-unique, demonstrating different args:

```ruby
IndexCustomer.enqueue(3)
... business logic
IndexCustomer.enqueue(426)
... business logic
IndexCustomer.enqueue(3)

=> Results in 2 index jobs, one with arg "3", one with arg "426"
```

Note, if you are attempting to prevent two identical jobs from executing concurrently that are
already enqueued, then you probably want to use another excellent
gem, [que-locks](https://github.com/airhorns/que-locks). Both that gem
and this one can be used in tandem, as they cover different use cases, and work at different levels
in the tech stack.

## Internal workings

Internally, `Que::Scheduler` works by aliasing the `ActiveRecord::Base.transaction` call, 
where it starts a thread local array which holds a hash of JSON strings of the arguments
that have been scheduled. We also start a monitor to check how deep we are in the
transaction nesting. If a nested transaction is detected, the increment goes up.

Once we detect that the transaction count has come back down to zero, we can conclude that we 
have left the transaction boundary, and the transaction is being committed. We enqueue the required
jobs and clear the thread locals.

## Development

1. Ensure you have a postgres running locally. You can do so easily with docker:
   ```bash
   docker run -p5432:5432 postgres:9.5.0
   ```
2. Check out this repo, then run the tests with the following:
   ```bash
   bundle install
   bundle exec rake spec
   ```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bambooengineering/que-unique.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
