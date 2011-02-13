Gem::Specification.new do |s|
  s.name = "daemon_controller"
  # Don't forget to update version.rb too.
  s.version = "0.2.6"
  s.date = "2011-02-13"
  s.summary = "A library for implementing daemon management capabilities"
  s.email = "hongli@phusion.nl"
  s.homepage = "http://github.com/FooBarWidget/daemon_controller/tree/master"
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
      "spec/unresponsive_daemon.rb"
  ]
end
