require "json"

module Slack
  module Resource
    macro included
      include JSON::Serializable
      include JSON::Serializable::Unmapped
    end
  end
end
