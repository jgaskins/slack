# slack

Slack API client, supporting both both HTTP and Socket mode.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     slack:
       github: jgaskins/slack
   ```

2. Run `shards install`

## Usage

To use the Slack API:

```crystal
require "slack"

slack = Slack::API::Client.new
```

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/jgaskins/slack/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
