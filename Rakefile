require_relative "lib/daemon_controller/version"

PACKAGE_NAME = "daemon_controller"
PACKAGE_VERSION = DaemonController::VERSION_STRING

desc "Run the unit tests"
task :test do
  ruby "-S rspec spec/*_spec.rb"
end

desc "Build & upload gem"
task "package:release" do
  sh "git tag -s release-#{PACKAGE_VERSION}"
  sh "gem build #{PACKAGE_NAME}.gemspec"
  puts "Proceed with pushing tag to Github and uploading the gem? [y/n]"
  if $stdin.readline == "y\n"
    sh "git push origin release-#{PACKAGE_VERSION}"
    sh "gem push #{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem"
  else
    puts "Did not upload the gem."
  end
end
