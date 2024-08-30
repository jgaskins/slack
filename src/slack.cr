require "http/web_socket"
require "http/client"
require "log"
require "json"
require "uri/json"
require "uuid/json"
require "db/pool"

module Slack
  VERSION = "0.1.0"
  Log     = ::Log.for(self)

  class Exception < ::Exception
    getter error : Error?

    def initialize(message : String? = nil, cause : Exception? = nil, *, @error = nil)
      super message, cause
    end
  end

  enum Error
    TooManyUsers
    UserNotFound
    UserNotVisible
    AccessDenied
    AccountInactive
    DeprecatedEndpoint
    EKMAccessDenied
    EnterpriseIsRestricted
    InvalidAuth
    MethodDeprecated
    MissingScope
    NotAllowedTokenType
    NotAuthed
    NoPermission
    OrgLoginRequired
    TokenExpired
    TokenRevoked
    TwoFactorSetupRequired
    Accesslimited
    FatalError
    InternalError
    InvalidArgName
    InvalidArguments
    InvalidArrayArg
    InvalidCharset
    InvalidFormData
    InvalidPostType
    MissingPostType
    Ratelimited
    RequestTimeout
    ServiceUnavailable
    TeamAddedToOrg
  end

  enum Warning
    MissingCharset
    SuperfluousCharset
  end

  class SocketClient
    getter state : State = :new
    getter log : ::Log
    @connection : HTTP::WebSocket
    @close_channel = Channel(Nil).new(1)

    enum State
      NEW
      CONNECTING
      CONNECTED
      DISCONNECTED
      CLOSED
    end

    def self.start(token : String)
      new(token).start
    end

    def initialize(@token : String = ENV["SLACK_SOCKET_TOKEN"], @log = Log)
      @state = :connecting
      @state, @connection = connect!
    end

    def received(event : Event)
      ack event
    end

    def received(event : EventsAPI)
      received event.payload
      ack event
    end

    def received(payload : EventCallback)
      received payload.event
    end

    private def ack(event : EventsAPI)
      @connection.send({envelope_id: event.envelope_id}.to_json)
    end

    def start
      spawn do
        connection = @connection
        until state.closed?
          begin
            sleep 10.seconds
            break if state.closed?
            @log.debug { "Ping..." }
            connection.ping
          rescue IO::Error
            disconnected! connection
            break
          end
        end
      end
      spawn @connection.run
      @close_channel.receive?
    end

    # Override this to handle errors
    def error(ex : ::Exception)
      log.error { ex }
      if trace = ex.backtrace?
        trace.each { |line| log.error { line } }
      end
    end

    def close
      @connection.close
    ensure
      @close_channel.close
      @state = :closed
    end

    private def disconnected!(connection)
      @state = :disconnected
      @log.debug { "Disconnected" }
      connection.close rescue nil # we don't care if this fails, we're just trying to clean up
      spawn reconnect! unless state.closed?
    end

    private def reconnect!
      @state, @connection = connect!
    end

    private def connect
      return if state.connected? || state.connecting?

      connect!
    end

    private def connect! : {State, HTTP::WebSocket}
      response = HTTP::Client.post("https://slack.com/api/apps.connections.open", headers: HTTP::Headers{"Authorization" => "Bearer #{@token}", "content-type" => "application/x-www-form-urlencoded"})
      result = Connections::OpenResult.from_json(response.body)
      if url = result.url
        @log.debug { "Connecting..." }
        connection = HTTP::WebSocket.new(url)
        connection.on_message do |body|
          @log.debug { body }
          spawn received(Event[body])
        rescue ex
          error ex
        end
        connection.on_close do
          disconnected! connection
        end
        connection.on_pong do
          @log.debug { "Pong" }
        end
        @log.debug { "Connected." }
        return State::CONNECTED, connection
      elsif error = result.error
        raise Exception.new(error)
      else
        raise Exception.new("Unexpected response from apps.connections.open request: #{response.body}")
      end
    end
  end

  module API
    class Client
      getter log : ::Log

      def initialize(@token : String = ENV["SLACK_API_TOKEN"], @log = Log)
        options = DB::Pool::Options.new(
          max_idle_pool_size: 6,
          max_pool_size: 10,
        )

        @pool = DB::Pool(HTTP::Client).new(options) do
          http = HTTP::Client.new(URI.parse("https://slack.com"))
          http.before_request do |req|
            req.headers["authorization"] = "Bearer #{token}"
            req.headers["content-type"] ||= "application/json; charset=utf-8"
          end
          http
        end
      end

      # Override this to handle errors
      def error(ex : ::Exception)
        log.error { ex }
        if trace = ex.backtrace?
          trace.each { |line| log.error { line } }
        end
      end

      def react_to(msg, with reaction : String)
        reactions.add(
          name: reaction,
          channel: msg.channel,
          timestamp: msg.ts,
        )
      end

      def reply_to(msg, text : String)
        chat.post_message(
          channel: msg.channel,
          text: text,
          thread_ts: msg.thread_ts || msg.ts,
        )
      end

      def mention(user : String)
        "<@#{user}>"
      end

      def chat
        Chat.new(self)
      end

      def conversations
        Conversations.new(self)
      end

      def reactions
        Reactions.new(self)
      end

      def users
        Users.new(self)
      end

      def auth
        Auth.new self
      end

      def get(method : String, *, params : URI::Params? = nil, return type : T.class) forall T
        response = @pool.checkout &.get("/api/#{method}?#{params}")

        if response.success?
          type.from_json(response.body)
        else
          raise Exception.new(Error.from_json(response.body).inspect)
        end
      end

      def post(method : String, *, body = nil, params : URI::Params? = nil, return type : T.class) forall T
        @pool.checkout &.post("/api/#{method}?#{params}", body: body.to_json) do |response|
          if response.success?
            type.from_json(response.body_io)
          else
            raise Exception.new(Error.from_json(response.body_io).inspect)
          end
        end
      end

      def get_file(file : ::Slack::File)
        headers = HTTP::Headers{"host" => file.permalink.host.to_s}
        @pool.checkout &.get file.permalink.request_target, headers: headers do |response|
          yield response
        end
      end
    end

    struct Error
      include JSON::Serializable

      getter? ok : Bool
      getter error : ::Slack::Error
    end

    struct PostMessageResponse
      include JSON::Serializable

      getter? ok : Bool
      getter channel : String
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
      def post_message(channel : String, text : String, thread_ts : String? = nil)
        body = {
          channel:   channel,
          text:      text,
          thread_ts: thread_ts,
        }
        @client.post "chat.postMessage", body: body, return: PostMessageResponse
      end
    end

    struct Conversations < API
      def replies(channel : String, ts : String)
        pp params = URI::Params{
          "channel" => channel,
          "ts"      => ts,
        }
        @client.get "conversations.replies", params: params, return: Replies
      end

      struct Replies
        include JSON::Serializable

        getter? ok : Bool
        @[JSON::Field(converter: ::Slack::API::Conversations::Replies::Messages)]
        getter messages : Array(Message | FileShare)
        getter? has_more : Bool

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
        params = URI::Params{
          "user" => user,
        }

        @client.post "users.info", params: params, return: UserResponse
      end

      def identity
        @client.post "users.identity", return: IdentityResponse
      end

      struct UserResponse
        include JSON::Serializable
        getter? ok : Bool
        getter user : User
      end

      struct User
        include JSON::Serializable
        getter id : String
        getter team_id : String
        getter name : String
        getter? deleted : Bool
        getter color : String
        getter real_name : String
        getter tz : String
        getter tz_label : String
        getter tz_offset : Int64

        macro predicate(*names)
          {% for name in names %}
            @[JSON::Field(key: "is_{{name.id}}")]
            getter? {{name.id}} : Bool = false
          {% end %}
        end

        predicate admin, owner, primary_owner, restricted, ultra_restricted, bot, app_user, email_confirmed
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

  class SocketAPIClient < API::Client
    @socket : SocketInterface

    def self.start(*, socket_token : String, api_token : String, log = Log)
      new(socket_token, api_token, log: log).start
    end

    def initialize(socket_token : String, api_token : String, log = Log)
      @socket = uninitialized SocketInterface # need this to be able to pass self
      @socket = SocketInterface.new(socket_token, self, log: log)
      super api_token, log
    end

    def received(event : EventsAPI)
      received event.payload
    end

    def received(payload : EventCallback)
      received payload.event
    end

    def received(payload)
    end

    def start
      @socket.start
    end

    def close : Nil
      @socket.close
    rescue ex : IO::Error # We don't care about IO errors, we're shutting down
    end

    def state
      @socket.state
    end

    class SocketInterface < SocketClient
      def initialize(token : String, @api : SocketAPIClient, log = Log)
        super token, log: log
      end

      def received(event : EventsAPI)
        @api.received event
        ack event
      end

      def received(event : Event)
        @api.received event
      end
    end
  end

  abstract struct Event
    include JSON::Serializable

    TYPE_MAP = Hash(String, Event.class).new

    getter type : String?

    macro handle(type)
      Event::TYPE_MAP[{{type.id.stringify}}] = {{@type}}
    end

    def self.[](json : String)
      Log.debug { json }
      parser = JSON::PullParser.new(json)
      parser.on_key "type" do
        name = parser.read_string
        if type = TYPE_MAP[name]?
          return type.from_json(json)
        end
      end
      UnknownEvent.from_json(json)
    end
  end

  struct EventsAPI < Event
    handle :events_api

    getter envelope_id : UUID
    getter payload : EventCallback
    getter? accepts_response_payload : Bool
    getter retry_attempt : Int32
    getter retry_reason : String
  end

  struct EventCallback
    include JSON::Serializable

    getter token : String
    getter team_id : String
    getter api_app_id : String
    getter event : Block
    getter event_id : String
    @[JSON::Field(converter: Time::EpochConverter)]
    getter event_time : Time
    getter authorizations : Array(Authorization)
    @[JSON::Field(key: "is_ext_shared_channel")]
    getter? ext_shared_channel : Bool
    getter event_context : String? # wat is this
  end

  abstract struct Block
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    # getter type : String?

    use_json_discriminator "type", {
      app_mention:            AppMention,
      broadcast:              Broadcast,
      emoji:                  Emoji,
      message:                Message,
      reaction_added:         ReactionAdded,
      reaction_removed:       ReactionRemoved,
      rich_text:              RichText,
      rich_text_quote:        RichTextQuote,
      rich_text_section:      RichTextSection,
      rich_text_list:         RichTextList,
      rich_text_preformatted: RichTextSection,
      text:                   Text,
      user:                   User,
    }
  end

  struct Message < Block
    getter client_msg_id : UUID = UUID.empty
    getter text : String
    getter user : String
    # @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter ts : String
    getter team : String?
    getter blocks : Array(Block) { [] of Block }
    getter channel : String = ""
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time = Time::UNIX_EPOCH
    # getter event_ts : String?
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter thread_ts : Time?
    # getter thread_ts : String?
    getter parent_user_id : String?
    getter channel_type : String?
    getter files : Array(Block) { [] of File }

    def self.new(pull : ::JSON::PullParser)
      location = pull.location

      discriminator_value = nil

      json = String.build do |io|
        JSON.build(io) do |builder|
          builder.start_object
          pull.read_object do |key|
            if key == "subtype"
              value_kind = pull.kind
              case value_kind
              when .string?
                discriminator_value = pull.string_value
              else
                raise ::JSON::SerializableError.new("JSON discriminator field '{{field.id}}' has an invalid value type of #{value_kind}", to_s, nil, *location, nil)
              end
              builder.field(key, discriminator_value)
              pull.read_next
            else
              builder.field(key) { pull.read_raw(builder) }
            end
          end
          builder.end_object
        end
      end

      case discriminator_value
      when nil               then new_from_json_pull_parser(JSON::PullParser.new(json))
      when "message_deleted" then MessageDeleted.from_json(json)
      when "message_changed" then MessageChanged.from_json(json)
      when "file_share"      then FileShare.from_json(json)
      else
        raise ::JSON::SerializableError.new("Unknown 'subtype' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
      end
    end
  end

  struct MessageDeleted < Block
    getter? hidden : Bool
    getter channel : String
    getter ts : String
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time
    getter channel_type : String
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter deleted_ts : Time
    getter previous_message : RelatedMessage?
  end

  struct MessageChanged < Block
    getter? hidden : Bool
    getter channel : String
    getter ts : String
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time
    getter channel_type : String
    getter message : RelatedMessage
    getter previous_message : RelatedMessage?
  end

  struct FileShare < Block
    getter client_msg_id : UUID
    getter text : String
    getter files : Array(File)
    getter? upload : Bool
    getter user : String
    getter? display_as_bot : Bool?
    getter ts : String
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time
    getter channel : String
    getter channel_type : String
    getter blocks : Array(Block) { [] of Block }
  end

  struct RelatedMessage < Block
    getter client_msg_id : UUID?
    getter text : String
    getter user : String
    getter ts : String
    getter team : String?
    getter source_team : String?
    getter user_team : String?
    getter blocks : Array(Block) { [] of Block }
    getter thread_ts : String?
    getter edited : Edited?
    getter files : Array(File) { [] of File }
    getter? upload : Bool?
    getter reply_count : Int32 = 0
    getter reply_users_count : Int32 = 0
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter latest_reply : Time?
    getter reply_users : Array(String) { [] of String }
    @[JSON::Field(key: "is_locked")]
    getter? locked : Bool?
    getter? subscribed : Bool?
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter last_read : Time?
    getter bot_id : String?
    getter app_id : String?
    getter bot_profile : BotProfile?
    getter parent_user_id : String?
    getter? display_as_bot : Bool?

    struct Edited
      include JSON::Serializable

      getter user : String
      @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
      getter ts : Time
    end

    struct BotProfile
      include JSON::Serializable

      getter id : String
      getter? deleted : Bool
      @[JSON::Field(converter: Time::EpochConverter)]
      getter updated : Time
      getter app_id : String
      getter icons : Hash(String, URI)
      getter team_id : String
    end
  end

  struct File < Block
    getter id : String
    @[JSON::Field(converter: Time::EpochConverter)]
    getter created : Time
    @[JSON::Field(converter: Time::EpochConverter)]
    getter timestamp : Time
    getter name : String
    getter title : String
    getter filetype : String?
    getter pretty_type : String?
    getter mimetype : String?
    getter user : String
    getter user_team : String
    getter? editable : Bool
    getter size : Int32
    getter mode : String
    @[JSON::Field(key: "is_external")]
    getter? is_external : Bool
    getter external_type : String
    @[JSON::Field(key: "is_public")]
    getter? public : Bool
    getter? public_url_shared : Bool
    getter? display_as_bot : Bool
    getter username : String
    getter url_private : URI
    getter url_private_download : URI
    getter permalink : URI
    getter permalink_public : URI
    getter edit_link : URI?
    getter preview : String?
    getter preview_highlight : String?
    getter lines : Int32?
    getter lines_more : Int32?
    @[JSON::Field(key: "preview_is_truncated")]
    getter? preview_truncated : Bool?
    @[JSON::Field(key: "is_starred")]
    getter? starred : Bool?
    getter? has_rich_preview : Bool?
    getter file_access : String? # enum?
    getter media_display_type : String?
    getter thumb_64 : URI?
    getter thumb_80 : URI?
    getter thumb_160 : URI?
    getter thumb_360 : URI?
    getter thumb_360_gif : URI?
    getter thumb_480 : URI?
    getter thumb_480_gif : URI?
    getter thumb_720 : URI?
    getter thumb_800 : URI?
    getter thumb_960 : URI?
    getter thumb_1024 : URI?
    getter thumb_tiny : URI?
    getter thumb_pdf : URI?
    getter transcription : Transcription?
    getter mp4 : URI?
    getter mp4_low : URI?
    getter deanimate_gif : URI?
    getter deanimate : URI?
    getter thumb_video : URI?

    struct Transcription
      include JSON::Serializable

      getter status : String
    end
  end

  struct AppMention < Block
    getter client_msg_id : UUID
    getter text : String
    getter user : String
    getter ts : String
    getter team : String?
    getter blocks : Array(Block)
    getter channel : String
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time
    getter thread_ts : String?
    getter parent_user_id : String?
    getter channel_type : String?
    getter edited : Edit?
    getter files : Array(File) { [] of File }

    struct Edit < Block
      getter user : String
      @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
      getter ts : Time
    end
  end

  abstract struct ReactionEvent < Block
    getter user : String
    getter reaction : String
    getter item_user : String
    getter item : Item
    @[JSON::Field(converter: Slack::StringifiedFloatTimestamp)]
    getter event_ts : Time

    struct Item < Block
      getter channel : String
      getter ts : String
    end
  end

  struct ReactionRemoved < ReactionEvent
  end

  struct ReactionAdded < ReactionEvent
  end

  struct RichText < Block
    getter block_id : String
    getter elements : Array(Block)
  end

  struct RichTextSection < Block
    getter elements : Array(Block)
  end

  struct RichTextQuote < Block
    getter elements : Array(Block)
  end

  struct RichTextList < Block
    include JSON::Serializable::Unmapped

    getter elements : Array(Block)
    getter style : Style
    getter indent : Int32
    getter border : Int32

    enum Style
      Ordered
      Bullet
    end
  end

  struct Broadcast < Block
    getter range : String
  end

  struct User < Block
    getter user_id : String
  end

  struct Emoji < Block
    getter name : String
    getter unicode : String?
  end

  struct Text < Block
    getter text : String
  end

  struct Authorization < Block
    getter enterprise_id : String?
    getter team_id : String
    getter user_id : String
    @[JSON::Field(key: "is_bot")]
    getter? bot : Bool
    @[JSON::Field(key: "is_enterprise_install")]
    getter? enterprise_install : Bool = false
  end

  struct UnknownEvent < Event
    getter data : JSON::Any

    def self.from_json(json)
      new JSON.parse(json)
    end

    def initialize(@data)
    end
  end

  struct Hello < Event
    handle :hello

    getter num_connections : Int64
    getter debug_info : DebugInfo
    getter connection_info : ConnectionInfo

    struct DebugInfo
      include JSON::Serializable

      getter host : String
      getter build_number : Int32
      getter approximate_connection_time : Int32
    end

    struct ConnectionInfo
      include JSON::Serializable

      getter app_id : String
    end
  end

  # :nodoc:
  struct Connections::OpenResult
    include JSON::Serializable

    getter? ok : Bool
    getter url : URI?
    getter error : String?
  end

  # :nodoc:
  module StringifiedFloatTimestamp
    def self.from_json(json : JSON::PullParser)
      Time::UNIX_EPOCH + json.read_string.to_f.seconds
    end

    def self.to_json(value : Time, json : JSON::Builder)
      json.string (value - Time::UNIX_EPOCH).total_seconds.to_s
    end
  end
end
