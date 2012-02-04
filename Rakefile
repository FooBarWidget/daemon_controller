verbose true

desc "Run the unit tests"
task :test do
	sh "rspec -f s -c spec/*_spec.rb"
end

task "package:gem" do
	sh "gem build daemon_controller.gemspec"
end
