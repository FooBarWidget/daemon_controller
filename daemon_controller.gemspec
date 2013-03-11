$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require 'daemon_controller/version'

Gem::Specification.new do |s|
  s.name = "daemon_controller"
  s.version = DaemonController::VERSION_STRING
  s.date = "2013-03-11"
  s.summary = "A library for implementing daemon management capabilities"
  s.email = "software-signing@phusion.nl"
  s.homepage = "https://github.com/FooBarWidget/daemon_controller"
  s.description = "A library for robust daemon management."
  s.has_rdoc = true
  s.authors = ["Hongli Lai"]
  
  s.files = [
      "README.markdown", "LICENSE.txt", "daemon_controller.gemspec",
      "lib/daemon_controller.rb",
      "lib/daemon_controller/lock_file.rb",
      "lib/daemon_controller/spawn.rb",
      "lib/daemon_controller/version.rb",
      "spec/test_helper.rb",
      "spec/daemon_controller_spec.rb",
      "spec/echo_server.rb",
      "spec/unresponsive_daemon.rb",
      "spec/run_echo_server"
  ]
  s.license = "MIT"
end
