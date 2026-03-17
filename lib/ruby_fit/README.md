# RubyFit

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library
into a gem. Put your Ruby code in the file `lib/ruby_fit`. To experiment with that code, run `bin/console` for an
interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after
releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section
with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ruby_fit.

```ruby
class FitCallbacks
  def print_msg(msg)
    puts msg
  end

  def on_file_id(msg)
    puts "file id: #{msg.inspect}"
  end

  def on_activity(msg)
    puts "activity: #{msg.inspect}"
  end

  def on_lap(msg)
    puts "lap: #{msg.inspect}"
  end

  #what is a session?  seems to be another way of saying activity...
  def on_session(msg)
    puts "session: #{msg.inspect}"
  end

  def on_record(msg)
    puts "record: #{msg.inspect}"
    cp = {}
    if msg['position_lat'] and msg['position_long']
      cp[:y] = ("%0.6f" % msg['position_lat']).to_f
      cp[:x] = ("%0.6f" % msg['position_long']).to_f
    end
    cp[:d] = msg['distance'] if msg['distance']
    cp[:e] = msg['altitude'] if msg['altitude']
    cp[:h] = msg['heart_rate'] if msg['heart_rate']
    cp[:t] = msg['timestamp']
    cp[:c] = msg['cadence'] if msg['cadence']
    cp[:p] = msg['power'] if msg['power']
    cp[:s] = msg['speed'] if msg['speed']
    cp[:T] = msg['temperature'] if msg['temperature']
  end

  def on_event(msg)
    puts "event: #{msg.inspect}"
  end

  def on_device_info(msg)
    puts "device info: #{msg.inspect}"
  end

  def on_user_profile(msg)
    puts "user profile: #{msg.inspect}"
  end

  def on_weight_scale_info(msg)
    puts "weight scale info: #{msg.inspect}"
  end
end

io = File.open('/Users/zombre98/project/velo/test/fixtures/files/fit/run.fit')
callbacks = FitCallbacks.new
parser = RubyFit::Parser.new(callbacks)
parser.parse(io)

```