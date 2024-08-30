module Slack::OAuth2
  abstract struct API
    protected getter client : Client

    def initialize(@client)
    end
  end
end
