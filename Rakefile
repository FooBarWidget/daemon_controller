require_relative "lib/daemon_controller/version"

PACKAGE_NAME = "daemon_controller"
PACKAGE_VERSION = DaemonController::VERSION_STRING

desc "Run the unit tests"
task :test do
  ruby "-S rspec spec/*_spec.rb"
end

desc "Build gem"
task :gem do
  mkdir_p "pkg"
  sh "gem build daemon_controller.gemspec -o pkg/#{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem"
end

desc "Build release artifacts"
task release: :gem do
  sh "gem push pkg/#{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem"
end
