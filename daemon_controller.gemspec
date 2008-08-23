Gem::Specification.new do |s|
  s.name = "daemon_controller"
  s.version = "0.2.0"
  s.date = "2008-08-21"
  s.summary = "A library for implementing daemon management capabilities"
  s.email = "hongli@phusion.nl"
  s.homepage = "http://github.com/FooBarWidget/daemon_controller/tree/master"
  s.description = "A library for implementing daemon management capabilities."
  s.has_rdoc = false
  s.authors = ["Hongli Lai"]
  
  s.files = [
      "README.rdoc", "LICENSE.txt", "daemon_controller.gemspec",
      "lib/daemon_controller.rb",
      "lib/daemon_controller/lock_file.rb",
      "spec/daemon_controller_spec.rb",
      "spec/echo_server.rb"
  ]
end
