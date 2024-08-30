require "./spec_helper"

require "../src/commands"

struct Rex::Commands::Test < Rex::Commands::Command
  command "omg-lol"
  args(
    name : String?,
    number : Int32?,
    timestamp : Time?,
  )
end

describe Rex::Commands do
  it "parses a command" do
    Rex::Commands::Command.parse("ping").should be_a Rex::Commands::Ping
  end

  it "parses a text command into a data structure" do
    parsed = Rex::ParsedCommand.new(%{foo bar baz omg=lol wtf="hello world" foo="bar"})

    parsed.command.should eq "foo"
    parsed.positional_args.should eq %w[bar baz]
    parsed.keyword_args.should eq({
      "omg" => "lol",
      "wtf" => "hello world",
      "foo" => "bar",
    })
  end

  it "parses non-string arguments" do
    timestamp = Time.utc
    parsed = Rex::Commands::Test.parse("omg-lol name=Jamie number=42 timestamp=#{timestamp.to_rfc3339(fraction_digits: 9)}")

    parsed.name.should eq "Jamie"
    parsed.number.should eq 42
    parsed.timestamp.should eq timestamp
  end
end
