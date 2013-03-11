$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require 'daemon_controller/version'

verbose true

desc "Run the unit tests"
task :test do
	sh "rspec -f s -c spec/*_spec.rb"
end

desc "Build, sign & upload gem"
task "package:upload" do
	sh "gem build daemon_controller.gemspec --sign --key 0x0A212A8C"
	puts "Proceed with uploading the gem? [y/n]"
	if STDIN.readline == "y\n"
		sh "gem push daemon_controller-#{DaemonController::VERSION_STRING}.gem"
	else
		puts "Did not upload the gem."
	end
end
