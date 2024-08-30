require "./command"

module Rex::Commands
  macro define(name, command, *args, &block)
    struct {{name}} < ::Rex::Commands::Command
      command {{command}}
      args {{args.splat}}

      {{yield}}
    end
  end

  define Hello, "hello", name : String = "world", emoji : String? = nil
  define Ping, "ping", timestamp : Time?
end
