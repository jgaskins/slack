require "./api"
require "./resource"

module Slack
  module OAuth2
    struct Reminders < API
      def list(token : String)
        [] of Reminder
      end
    end

    class Client
      def reminders
        Reminders.new self
      end
    end
  end

  struct Reminder
    include Resource
  end
end
