require "string_scanner"
require "./rex"

class Rex
  private REGISTRY = {} of String => Commands::Command.class

  module Commands
    abstract struct Command
      def self.parse(text : String)
        command = text[/\A[\w-]+\b/]?
        if type = REGISTRY[command]?
          type
        else
          type = Unknown
        end

        type.parse(text)
      end

      def self.command
        raise NotImplementedError.new(name)
      end

      def self.args
        Tuple.new
      end

      def self.register(name : String, event_class : Command.class)
        REGISTRY[name] = event_class
      end

      macro inherited
        def self.parse(text : String)
          new
        end
      end

      macro command(name)
        ::Rex::Commands::Command.register {{name.id.stringify}}, self
        def self.command
          {{name}}
        end
      end

      struct Arg(DefaultType, Type)
        getter name : String
        getter default : DefaultType?
        getter type : Type.class

        def initialize(@name, @default, @type)
        end

        def optional? : Bool
          !!({{Type.nilable?}} || @default)
        end
      end

      macro args(*args)
        {% for arg in args %}
          {% unless arg.value || arg.type.resolve.nilable? %}
            {% raise "Command arguments must either be nilable or have a default value: #{@type} - #{arg}" %}
          {% end %}
          getter {{arg}}
        {% end %}

        def self.parse(text : String)
          parsed = ::Rex::ParsedCommand.new(text)
          index = 0
          {% for arg in args %}
            var = parsed.keyword_args.fetch("{{arg.var}}") do
              value = parsed.positional_args.fetch(index) do
                index -= 1
                {{arg.value || nil}}
              end
              index += 1
              value
            end
            %var{arg.var} = ({{arg.type}}).from_rex_value(var)
          {% end %}

          new(
            {% for arg in args %}
              {{arg.var}}: %var{arg.var},
            {% end %}
          )
        end

        def initialize(
          *,
          {% for arg in args %}
            {% if arg.var %}
              {% if arg.type %}
                @{{arg.var}} : {{arg.type}}{% if arg.value %} = {{arg.value}}{% end %},
              {% else %}
                {% raise "Must specify type for arg #{arg}" %}
              {% end %}
            {% end %}
          {% end %}
        )
        end

        def self.args
          {
            {% for arg in args %}
              Arg.new(
                name: "{{arg.var}}",
                default: {{arg.value || nil}},
                type: {{arg.type}},
              ),
            {% end %}
          }
        end
      end
    end

    struct Unknown < Command
    end

    struct Help < Command
      command "help"
      args command : String?

      def text
        if (command = commands[self.command]?)
          reply = String.build { |str| info command, str }
        else
          reply = String.build do |str|
            commands
              .to_a
              .sort_by { |(_, command)| command.command }
              .each { |(_, command)| info command, str }
          end
        end
      end

      def info(command : Commands::Command.class, str : String::Builder)
        str.puts "- `#{command.command}`"
        command.args.each do |arg|
          str << "   - `#{arg.name}`: `#{arg.type}`"
          if arg.optional? || arg.default
            str << " ("

            str << "optional" if arg.optional?
            str << ", " if arg.optional? && arg.default
            if arg.default
              str << "default: `"
              arg.default.inspect str
              str << '`'
            end

            str.puts ")"
          end
        end
      end

      def commands
        REGISTRY.dup
      end
    end
  end

  struct ParsedCommand
    getter command : String
    getter positional_args = [] of String
    getter keyword_args = {} of String => String

    def initialize(text : String)
      parser = Parser.new(text)
      if command = parser.read_command
        @command = command
      else
        raise ArgumentError.new("Invalid command: #{text.inspect}")
      end
      while arg = parser.read_positional_arg
        positional_args << arg
      end
      while arg = parser.read_keyword_arg
        key, value = arg
        keyword_args[key] = value
      end
    end

    class Parser
      @cursor = 0

      def initialize(@string : String)
      end

      def read_command
        return if @cursor >= @string.size

        skip_whitespace
        consume_until &.whitespace?
      end

      def read_positional_arg
        return if @cursor >= @string.size

        skip_whitespace
        cursor = @cursor
        arg = consume_value
        if arg.try &.includes? '='
          @cursor = cursor
          nil
        else
          arg
        end
      end

      def read_keyword_arg
        return if @cursor >= @string.size

        skip_whitespace
        if (key = consume_key) && (value = consume_value)
          {key, value}
        end
      end

      private def consume_key
        return if @cursor >= @string.size

        skip_whitespace
        key = consume_until { |c| c == '=' }
        skip_whitespace
        key
      end

      private def consume_value
        return if @cursor >= @string.size

        skip_whitespace
        if current_char == '"'
          next_char
          consume_until { |c| c == '"' }
        else
          consume_until(&.whitespace?)
        end
      end

      def next_char
        @cursor += 1
        current_char
      end

      def current_char
        @string[@cursor]
      end

      private def skip_whitespace
        return if @cursor >= @string.size

        while @string[@cursor]?.try(&.whitespace?)
          @cursor += 1
        end
      end

      private def consume_until
        return if @cursor >= @string.size

        String.build do |str|
          (@cursor...@string.size).each do |index|
            char = @string[index]
            @cursor = index + 1
            break if yield(char) || @cursor >= @string.size + 1
            str << char
          end
        end
      end
    end
  end
end

def Union.from_rex_value(value : String?)
  if value
    {% begin %}
      {% for type in T %}
        {{type}}.from_rex_value(value) ||
      {% end %}
      nil
    {% end %}
  end
end

def Time.from_rex_value(string : String)
  rfc_3339 = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
  rfc_2822 = /\w{3},? \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2}/

  case string
  when rfc_3339
    Format::RFC_3339.parse string
  when rfc_2822
    Format::RFC_2822.parse string
  else
    Format::HTTP_DATE.parse string
  end
end

def Nil.from_rex_value(value)
end

def String.from_rex_value(value : String)
  value
end

def Int32.from_rex_value(value : String)
  value.to_i
end
