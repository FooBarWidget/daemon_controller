$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require "daemon_controller/version"

PACKAGE_NAME = "daemon_controller"
PACKAGE_VERSION = DaemonController::VERSION_STRING
PACKAGE_SIGNING_KEY = "0x0A212A8C"

desc "Run the unit tests"
task :test do
  ruby "-S rspec -f documentation -c spec/*_spec.rb"
end

desc "Build, sign & upload gem"
task "package:release" do
  sh "git tag -s release-#{PACKAGE_VERSION}"
  sh "gem build #{PACKAGE_NAME}.gemspec --sign --key #{PACKAGE_SIGNING_KEY}"
  puts "Proceed with pushing tag to Github and uploading the gem? [y/n]"
  if STDIN.readline == "y\n"
    sh "git push origin release-#{PACKAGE_VERSION}"
    sh "gem push #{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem"
  else
    puts "Did not upload the gem."
  end
end
