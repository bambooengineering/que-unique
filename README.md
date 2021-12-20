# Que::Unique

The goal of Que::Unique is to ensure that a job is not scheduled twice during a transaction
block. A typical use case would be modifying a customer at various points during a code route,
and wanting to index it once in elasticsearch afterwards.

To do this, we must alias the ActiveRecord::Base.transaction call, to start a thread local
array which holds a hash of JSON strings of the arguments that have been scheduled.
We also start a monitor to check how deep we are in the transaction nesting. Once we have
left the transaction boundary, we clear the thread locals.

Use:

```ruby
# Add to Gemfile
gem 'que-unique'

# Add the `include` to your job
class SomeUniqueJob < Que::Job
 include Que::Unique
end
```

Now, in a transaction, only one of that set of args (as json'd) will be enqueued.

## Development

1. Ensure you have a postgres running locally. You can do so easily with docker:
   `docker run -p5432:5432 postgres:9.5.0`
2. Check out this repo, then run the tests with the following:
```bash
bundle install
bundle exec rake spec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bambooengineering/que-unique.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
