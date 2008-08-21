desc "Run the unit tests"
task :test do
	sh "spec -f s -c spec/daemon_controller_spec.rb"
end

task "package:gem" do
	sh "gem build daemon_controller.gemspec"
end
