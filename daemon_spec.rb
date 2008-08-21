require 'daemon_controller'
require 'benchmark'
require 'socket'

# A thread which doesn't execute its block until the
# 'go!' method has been called.
class WaitingThread < Thread
	def initialize
		super do
			@mutex = Mutex.new
			@cond = ConditionVariable.new
			@go = false
			@mutex.synchronize do
				while !@go
					@cond.wait(@mutex)
				end
			end
			yield
		end
	end
	
	def go!
		@mutex.synchronize do
			@go = true
			@cond.broadcast
		end
	end
end

module TestHelpers
	def new_controller(options = {})
		start_command = './echo_server.rb -l echo_server.log -P echo_server.pid'
		if options[:wait1]
			start_command << " --wait1 #{options[:wait1]}"
		end
		if options[:wait2]
			start_command << " --wait2 #{options[:wait2]}"
		end
		new_options = {
			:identifier    => 'My Test Daemon',
			:start_command => start_command,
			:ping_command  => proc do
				begin
					TCPSocket.new(localhost, 3230)
					true
				rescue
					false
				end
			end,
			:pid_file => 'echo_server.pid',
			:log_file => 'echo_server.log'
		}.merge(options)
		@controller = DaemonController.new(new_options)
	end
	
	def write_file(filename, contents)
		File.open(filename, 'w') do |f|
			f.write(contents)
		end
	end
end

describe DaemonController, "#start" do
	before :each do
		new_controller
	end
	
	include TestHelpers
	
	it "raises AlreadyStarted if the daemon is already running" do
		@controller.should_receive(:daemon_is_running?).and_return(true)
		lambda { @controller.start }.should raise_error(DaemonController::AlreadyStarted)
	end
	
	it "deletes existing PID file before starting the daemon" do
		write_file('echo_server.pid', '1234')
		@controller.should_receive(:daemon_is_running?).and_return(false)
		@controller.should_receive(:spawn_daemon)
		@controller.should_receive(:wait_until_pid_file_is_available)
		@controller.should_receive(:wait_until_daemon_responds_to_ping_or_has_exited).and_return(true)
		@controller.start
		File.exist?('echo_server.pid').should be_false
	end
	
	it "blocks until the daemon has written to its PID file" do
		thread = WaitingThread.new do
			sleep 0.15
			write_file('echo_server.pid', '1234')
		end
		@controller.should_receive(:daemon_is_running?).and_return(false)
		@controller.should_receive(:spawn_daemon).and_return do
			thread.go!
		end
		@controller.should_receive(:wait_until_daemon_responds_to_ping_or_has_exited).and_return(true)
		begin
			result = Benchmark.measure do
				@controller.start
			end
			(0.15 .. 0.30).should === result.real
		ensure
			thread.join
		end
	end
	
	it "blocks until the daemon can be pinged" do
		ping_ok = false
		running = false
		new_controller(:ping_command => lambda { ping_ok })
		thread = WaitingThread.new do
			sleep 0.15
			ping_ok = true
		end
		@controller.should_receive(:daemon_is_running?).at_least(:once).and_return do
			running
		end
		@controller.should_receive(:spawn_daemon).and_return do
			thread.go!
			running = true
		end
		@controller.should_receive(:wait_until_pid_file_is_available)
		begin
			result = Benchmark.measure do
				@controller.start
			end
			(0.15 .. 0.30).should === result.real
		ensure
			thread.join
		end
	end
	
	it "raises StartTimeout if the daemon doesn't start in time"
	it "raises StartError if the daemon exits with an error before forking"
	it "raises StartError if the daemon exits with an error after forking"
	specify "the daemon's error output before forking is made available in the exception"
	specify "the daemon's error output after forking is made available in the exception"
	it "waits until no other process is starting, stopping or reading process information from a daemon with the same identifier"
	
	describe "if ping command a command" do
		it "checks whether the ping command exits with 0 to check whether the server can be pinged"
		it "raises an exception with the ping command's error message if the ping command exits with non-0"
	end
	
	describe "if ping command is a proc" do
		it "calls the ping proc to check whether the server can be pinged"
		it "forwards exceptions raised by the ping proc"
	end
end

describe DaemonController, "#stop" do
	it "raises no exception if the daemon is not running"
	it "waits until no other process is starting, stopping or reading process information from a daemon with the same identifier"
	
	describe "if stop command was given" do
		it "kills the daemon with the stop command"
		it "raises an error if the stop command exits with an error"
		it "makes the stop command's error message available in the exception"
	end
	
	describe "if no stop command was given" do
		it "kills the daemon by sending the pid in the pid file a signal"
		it "raises StopError if the daemon cannot be signalled"
	end
end

describe DaemonController, "#connect" do
end

describe DaemonController, "#running?" do
end

describe DaemonController, "#pid" do
end

