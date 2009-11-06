require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))
require 'daemon_controller'
require 'benchmark'
require 'socket'

describe DaemonController, "#start" do
	before :each do
		new_controller
	end
	
	include TestHelper
	
	it "works" do
		@controller.start
		@controller.stop
	end
	
	it "raises AlreadyStarted if the daemon is already running" do
		@controller.should_receive(:daemon_is_running?).and_return(true)
		lambda { @controller.start }.should raise_error(DaemonController::AlreadyStarted)
	end
	
	it "deletes existing PID file before starting the daemon" do
		write_file('spec/echo_server.pid', '1234')
		@controller.should_receive(:daemon_is_running?).and_return(false)
		@controller.should_receive(:spawn_daemon)
		@controller.should_receive(:pid_file_available?).and_return(true)
		@controller.should_receive(:run_ping_command).at_least(:once).and_return(true)
		@controller.start
		File.exist?('spec/echo_server.pid').should be_false
	end
	
	it "blocks until the daemon has written to its PID file" do
		thread = WaitingThread.new do
			sleep 0.15
			write_file('spec/echo_server.pid', '1234')
		end
		@controller.should_receive(:daemon_is_running?).and_return(false)
		@controller.should_receive(:spawn_daemon).and_return do
			thread.go!
		end
		@controller.should_receive(:run_ping_command).at_least(:once).and_return(true)
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
		@controller.should_receive(:pid_file_available?).and_return(true)
		@controller.should_receive(:run_ping_command).at_least(:once).and_return do
			ping_ok
		end
		begin
			result = Benchmark.measure do
				@controller.start
			end
			(0.15 .. 0.30).should === result.real
		ensure
			thread.join
		end
	end
	
	it "raises StartTimeout if the daemon doesn't start in time" do
		if exec_is_slow?
			start_timeout = 4
			min_start_timeout = 0
			max_start_timeout = 6
		else
			start_timeout = 0.15
			min_start_timeout = 0.15
			max_start_timeout = 0.30
		end
		new_controller(:start_command => 'sleep 2', :start_timeout => start_timeout)
		start_time = Time.now
		end_time = nil
		@controller.should_receive(:start_timed_out).and_return do
			end_time = Time.now
		end
		begin
			lambda { @controller.start }.should raise_error(DaemonController::StartTimeout)
			(min_start_timeout .. max_start_timeout).should === end_time - start_time
		ensure
			@controller.stop
		end
	end
	
	it "kills the daemon with a signal if the daemon doesn't start in time and there's a PID file" do
		new_controller(:wait2 => 3, :start_timeout => 1)
		pid = nil
		@controller.should_receive(:start_timed_out).and_return do
			@controller.send(:wait_until) do
				@controller.send(:pid_file_available?)
			end
			pid = @controller.send(:read_pid_file)
		end
		begin
			lambda { @controller.start }.should raise_error(DaemonController::StartTimeout)
		ensure
			# It's possible that because of a racing condition, the PID
			# file doesn't get deleted before the next test is run. So
			# here we ensure that the PID file is gone.
			File.unlink("spec/echo_server.pid") rescue nil
		end
	end
	
	if DaemonController.send(:fork_supported?)
		it "kills the daemon if it doesn't start in time and hasn't " <<
		   "forked yet, on platforms where Ruby supports fork()" do
			new_controller(:start_command => '(echo $$ > spec/echo_server.pid && sleep 5)',
				:start_timeout => 0.3)
			lambda { @controller.start }.should raise_error(DaemonController::StartTimeout)
		end
	end
	
	it "raises an error if the daemon exits with an error before forking" do
		new_controller(:start_command => 'false')
		lambda { @controller.start }.should raise_error(DaemonController::Error)
	end
	
	it "raises an error if the daemon exits with an error after forking" do
		new_controller(:crash_before_bind => true, :log_file_activity_timeout => 0.2)
		lambda { @controller.start }.should raise_error(DaemonController::Error)
	end
	
	specify "the daemon's error output before forking is made available in the exception" do
		new_controller(:start_command => '(echo hello world; false)')
		begin
			@controller.start
		rescue DaemonController::Error => e
			e.message.should == "hello world"
		end
	end
	
	specify "the daemon's error output after forking is made available in the exception" do
		new_controller(:crash_before_bind => true, :log_file_activity_timeout => 0.1)
		begin
			@controller.start
			violated
		rescue DaemonController::StartTimeout => e
			e.message.should =~ /crashing, as instructed/
		end
	end
end

describe DaemonController, "#stop" do
	include TestHelper
	
	before :each do
		new_controller
	end
	
	after :each do
		@controller.stop
	end
	
	it "raises no exception if the daemon is not running" do
		@controller.stop
	end
	
	it "waits until the daemon is no longer running" do
		new_controller(:stop_time => 0.3)
		@controller.start
		result = Benchmark.measure do
			@controller.stop
		end
		@controller.should_not be_running
		(0.3 .. 0.6).should === result.real
	end
	
	it "raises StopTimeout if the daemon does not stop in time" do
		new_controller(:stop_time => 0.3, :stop_timeout => 0.1)
		@controller.start
		begin
			lambda { @controller.stop }.should raise_error(DaemonController::StopTimeout)
		ensure
			new_controller.stop
		end
	end
	
	describe "if stop command was given" do
		it "raises StopError if the stop command exits with an error" do
			new_controller(:stop_command => '(echo hello world; false)')
			begin
				begin
					@controller.stop
					violated
				rescue DaemonController::StopError => e
					e.message.should == 'hello world'
				end
			ensure
				new_controller.stop
			end 
		end
		
		it "makes the stop command's error message available in the exception" do
		end
	end
end

describe DaemonController, "#connect" do
	include TestHelper
	
	before :each do
		new_controller
	end
	
	it "starts the daemon if it isn't already running" do
		socket = @controller.connect do
			TCPSocket.new('localhost', 3230)
		end
		socket.close
		@controller.stop
	end
	
	it "connects to the existing daemon if it's already running" do
		@controller.start
		begin
			socket = @controller.connect do
				TCPSocket.new('localhost', 3230)
			end
			socket.close
		ensure
			@controller.stop
		end
	end
end

describe DaemonController do
	include TestHelper
	
	specify "if the ping command is a block that raises Errno::ECONNREFUSED, then that's " <<
	        "an indication that the daemon cannot be connected to" do
		new_controller(:ping_command => lambda do
			raise Errno::ECONNREFUSED, "dummy"
		end)
		@controller.send(:run_ping_command).should be_false
	end
	
	specify "if the ping command is a block that returns an object that responds to #close, " <<
	        "then the close method will be called on that object" do
		server = TCPServer.new('localhost', 8278)
		begin
			socket = nil
			new_controller(:ping_command => lambda do
				socket = TCPSocket.new('localhost', 8278)
			end)
			@controller.send(:run_ping_command)
			socket.should be_closed
		ensure
			server.close
		end
	end
	
	specify "if the ping command is a block that returns an object that responds to #close, " <<
	        "and #close raises an exception, then that exception is ignored" do
		server = TCPServer.new('localhost', 8278)
		begin
			o = Object.new
			o.should_receive(:close).and_return do
				raise StandardError, "foo"
			end
			new_controller(:ping_command => lambda do
				o
			end)
			lambda { @controller.send(:run_ping_command) }.should_not raise_error(StandardError)
		ensure
			server.close
		end
	end
end
