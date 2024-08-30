require "slack"

# Log.setup :debug

class Rex < Slack::SocketAPIClient
  def received(hello : Slack::Hello)
    pp hello: hello
  end

  def received(hello : Commands::Hello, message)
    reply = "hello #{hello.name}!"
    if emoji = hello.emoji
      reply += " :#{emoji}:"
    end

    reply_to message, reply
  end

  def received(ping : Commands::Ping, message)
    timestamp = ping.timestamp || message.event_ts
    latency = Time.utc - timestamp
    reply = "pong! #{latency}"

    reply_to message, reply
  end

  def received(help : Commands::Help, message)
    reply_to message, help.text
  end

  def received(command : Commands::Unknown, message)
    reply_to message, "Unknown command: #{message.text.inspect}"
  end

  def received(file_share : Slack::FileShare)
    pp file_share: file_share
  end

  def received(msg : Slack::Message)
    pp msg: msg
  end

  def received(event : Slack::MessageChanged | Slack::MessageDeleted)
    pp event
  end

  def received(thing)
    pp thing: thing
  end

  # When someone adds a ✅ emoji, we also add a 🙌
  def received(event : Slack::ReactionAdded)
    if event.reaction == "white_check_mark"
      react_to event.item, with: "raised_hands"
    end
  end

  def received(event : Slack::ReactionRemoved)
    if event.reaction == "white_check_mark"
      msg = event.item

      reactions.remove(
        name: "raised_hands",
        channel: msg.channel,
        timestamp: msg.ts,
      )
    end
  end

  def received(mention : Slack::AppMention)
    command_text = mention.text.gsub(/\A<@\w+> /, "")

    received Commands::Command.parse(command_text), mention
  rescue exception
    reply_to mention, <<-ERROR
      Error occurred while processing:
      `#{exception.class}`: `#{exception}`
      ERROR
  end
end

# Load all the commands
require "./commands"

rex = Rex.new(
  socket_token: ENV["SLACK_SOCKET_TOKEN"],
  api_token: ENV["SLACK_API_TOKEN"],
)

spawn rex.start

signals = [:int, :term] of Signal
signals.each &.trap { rex.close }

while rex.state.connected?
  sleep 100.milliseconds
end
