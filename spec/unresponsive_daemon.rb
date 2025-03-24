#!/usr/bin/env ruby
# frozen_string_literal: true

dir = File.dirname(__FILE__)
Dir.chdir(File.dirname(dir))
begin
  File.open("spec/echo_server.pid", "w") do |f|
    f.puts(Process.pid)
  end
  sleep 30
rescue SignalException
  begin
    File.unlink("spec/echo_server.pid")
  rescue
    nil
  end
  raise
end
