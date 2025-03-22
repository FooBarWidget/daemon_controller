require_relative "lib/daemon_controller/version"
require_relative "lib/daemon_controller/packaging"

Gem::Specification.new do |s|
  s.name = "daemon_controller"
  s.version = DaemonController::VERSION_STRING
  s.summary = "A library for implementing daemon management capabilities"
  s.email = "software-signing@phusion.nl"
  s.homepage = "https://github.com/FooBarWidget/daemon_controller"
  s.description = "A library for robust daemon management."
  s.license = "MIT"
  s.authors = ["Hongli Lai"]
  s.files = Dir[*DAEMON_CONTROLLER_FILES]
  s.required_ruby_version = ">= 2.0.0"
end
