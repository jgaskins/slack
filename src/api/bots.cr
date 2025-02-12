require "./api"

module Slack::API
  struct Bots < API
    def info
      @client.get "bots.info", return: JSON::Any
    end
  end
end
