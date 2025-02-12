module Slack
  module API
    struct Error
      include JSON::Serializable

      getter? ok : Bool
      getter error : ::Slack::Error
    end

    struct PostMessageResponse
      include JSON::Serializable

      getter? ok : Bool
      getter channel : String?
      getter ts : String
      getter message : JSON::Any # Message
      getter warning : String?
      # getter response_metadata
    end

    abstract struct API
      def initialize(@client : Client)
      end
    end

    struct Chat < API
      def post_message(channel : String, blocks : Array(Block), thread_ts : String? = nil)
        body = {
          channel:   channel,
          blocks:    blocks,
          thread_ts: thread_ts,
        }

        result = @client.post "chat.postMessage", body: body, return: PostMessageResponse | Error
        case result
        in PostMessageResponse
          result
        in Error
          pp result
          raise Exception.new(result.errors.join(", "), error: result.error)
        end
      end

      def post_message(channel : String, text : String, thread_ts : String? = nil)
        body = {
          channel:   channel,
          text:      text,
          thread_ts: thread_ts,
        }
        @client.post "chat.postMessage", body: body, return: PostMessageResponse
      end

      struct Error
        include JSON::Serializable
        include JSON::Serializable::Unmapped

        getter? ok : Bool
        getter error : ::Slack::Error
        getter errors : Array(String) { [] of String }
        getter response_metadata : Hash(String, Array(String)) { {} of String => Array(String) }
      end
    end

    struct Conversations < API
      def replies(channel : String, ts : String)
        params = URI::Params{
          "channel" => channel,
          "ts"      => ts,
        }
        @client.get "conversations.replies", params: params, return: Replies
      end

      struct Replies
        include JSON::Serializable
        # include Enumerable(Message | FileShare)

        getter? ok : Bool
        @[JSON::Field(converter: ::Slack::API::Conversations::Replies::Messages)]
        getter messages : Array(Message | FileShare)
        getter? has_more : Bool

        delegate each, to: messages

        module Messages
          extend self

          def self.from_json(json : JSON::PullParser)
            messages = [] of Message | FileShare
            json.read_array do
              messages << Message.new(json).as(Message | FileShare)
            end
            messages
          end
        end
      end
    end

    struct Auth < API
      def test
        @client.get "auth.test", return: Test
      end

      struct Test
        include JSON::Serializable

        getter? ok : Bool
        getter url : URI
        getter team : String
        getter user : String
        getter team_id : String
        getter user_id : String
      end
    end

    struct Users < API
      def info(user : String)
        user = user.strip
        if user.starts_with?("<@") && user.ends_with?(">")
          user = user[2..-2]
        end
        params = URI::Params{"user" => user}

        @client.post "users.info", params: params, return: UserResponse
      end

      def list(
        cursor : String? = nil,
        include_locale : Bool = false,
        limit : Int? = nil,
        team_id : String? = nil,
      )
        params = URI::Params.new
        params["cursor"] = cursor.to_s if cursor
        params["include_locale"] = include_locale.to_s if include_locale
        params["limit"] = limit.to_s if limit
        params["team_id"] = team_id.to_s if team_id

        @client.get "users.list", params: params, return: UserListResponse
      end

      def identity
        @client.post "users.identity", return: IdentityResponse
      end

      struct UserResponse
        include JSON::Serializable
        getter? ok : Bool
        getter user : User
      end

      struct UserListResponse
        include JSON::Serializable

        getter? ok : Bool
        getter members : Array(User)
      end

      struct User
        include JSON::Serializable
        include JSON::Serializable::Unmapped

        getter id : String
        getter team_id : String
        getter name : String
        getter? deleted : Bool
        getter color : String
        getter real_name : String
        getter tz : String
        getter tz_label : String
        getter tz_offset : Int64
        @[JSON::Field(converter: Time::EpochConverter)]
        getter updated : Time?
        getter profile : Profile
        getter who_can_share_contact_card : JSON::Any

        macro predicate(*names)
          {% for name in names %}
            @[JSON::Field(key: "is_{{name.id}}")]
            getter? {{name.id}} : Bool?
          {% end %}
        end

        predicate admin, owner, primary_owner, restricted, ultra_restricted, bot, app_user, email_confirmed

        struct Profile
          include JSON::Serializable

          getter title : String
          getter phone : String
          getter skype : String
          getter real_name : String
          getter real_name_normalized : String
          getter display_name : String
          getter display_name_normalized : String
          getter fields : JSON::Any
          getter status_text : String
          getter status_emoji : String
          getter status_emoji_display_info : Array(JSON::Any)
          @[JSON::Field(converter: Time::EpochConverter)]
          getter status_expiration : Time
          getter avatar_hash : String
          getter api_app_id : String?
          getter? always_active : Bool?
          getter bot_id : String?
          getter first_name : String
          getter last_name : String
          getter image_24 : String
          getter image_32 : String
          getter image_48 : String
          getter image_72 : String
          getter image_192 : String
          getter image_512 : String
          getter status_text_canonical : String
          getter team : String
        end
      end

      struct IdentityResponse
        include JSON::Serializable
        getter? ok : Bool
        getter user : UserIdentity
        getter team : TeamIdentity

        struct UserIdentity
          include JSON::Serializable
          getter name : String
          getter id : String
          getter email : String?
        end

        struct TeamIdentity
          include JSON::Serializable
          getter id : String
        end
      end
    end

    struct Reactions < API
      def add(name : String, channel : String, timestamp : String)
        body = {
          name:      name,
          channel:   channel,
          timestamp: timestamp,
        }

        @client.post "reactions.add", body: body, return: JSON::Any
      end

      def remove(name : String, channel : String, timestamp : String)
        body = {
          name:      name,
          channel:   channel,
          timestamp: timestamp,
        }

        @client.post "reactions.remove", body: body, return: JSON::Any
      end
    end
  end
end
