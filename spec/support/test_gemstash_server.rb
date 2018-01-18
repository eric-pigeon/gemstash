require "gemstash"
require "puma/cli"
require "support/server_check"

# Launches a test Gemstash server directly via Puma.
class TestGemstashServer
  attr_reader :env

  def initialize(port: nil, config: nil)
    raise "Port is required" unless port
    raise "Config is required" unless config
    @port = port
    args = %w[--config -]
    args += %w[--workers 0]
    args += %w[--threads 0:4]
    args += %w[--environment test]
    args += ["--port", port.to_s]
    args << File.expand_path("../test_gemstash_server.ru", __FILE__)
    config = Gemstash::Configuration.new(config: config)
    cache = Gemstash::Env.current.cache
    db = Gemstash::Env.current.db
    @env = Gemstash::Env.new(config, cache: cache, db: db)
    # rubocop:disable Style/GlobalVars
    $test_gemstash_server_env = @env
    # rubocop:enable Style/GlobalVars
    @puma_cli = Puma::CLI.new(args)
    TestGemstashServer.servers << self
  end

  def url
    "http://127.0.0.1:#{@port}"
  end

  def upstream
    @upstream ||= Gemstash::Upstream.new(url)
  end

  def private_upstream
    @private_upstream ||= Gemstash::Upstream.new(upstream.url("private"))
  end

  def start
    raise "Already started!" if @started
    @started = true

    @thread = Thread.new do
      @puma_cli.run
    end

    ServerCheck.new(@port).wait
  end

  def stop
    return if @stopped
    @stopped = true
    @puma_cli.launcher.stop
  end

  def join
    raise "Only join if stopping!" unless @stopped
    return if @thread.join(10)
    puts "WARNING: TestGemstashServer is not stopping!"
  end

  def self.join_all
    servers.each(&:join)
  end

  def self.servers
    @servers ||= []
  end
end
