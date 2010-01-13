root = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$LOAD_PATH.unshift(File.join(root, "lib"))
Dir.chdir(root)

module TestHelper
	def new_controller(options = {})
		@start_command = './spec/echo_server.rb -l spec/echo_server.log -P spec/echo_server.pid'
		if options[:wait1]
			@start_command << " --wait1 #{options[:wait1]}"
		end
		if options[:wait2]
			@start_command << " --wait2 #{options[:wait2]}"
		end
		if options[:stop_time]
			@start_command << " --stop-time #{options[:stop_time]}"
		end
		if options[:crash_before_bind]
			@start_command << " --crash-before-bind"
		end
		if options[:no_daemonize]
			@start_command << " --no-daemonize"
		end
		new_options = {
			:identifier    => 'My Test Daemon',
			:start_command => @start_command,
			:ping_command  => method(:ping_echo_server),
			:pid_file      => 'spec/echo_server.pid',
			:log_file      => 'spec/echo_server.log',
			:start_timeout => 3,
			:stop_timeout  => 3
		}.merge(options)
		@controller = DaemonController.new(new_options)
	end
	
	def ping_echo_server
		begin
			TCPSocket.new('127.0.0.1', 3230)
			true
		rescue SystemCallError
			false
		end
	end
	
	def write_file(filename, contents)
		File.open(filename, 'w') do |f|
			f.write(contents)
		end
	end
	
	def exec_is_slow?
		return RUBY_PLATFORM == "java"
	end
	
	def process_is_alive?(pid)
		begin
			Process.kill(0, pid)
			return true
		rescue Errno::ESRCH
			return false
		rescue SystemCallError => e
			return true
		end
	end
	
	def eventually(deadline_duration = 1, check_interval = 0.05)
		deadline = Time.now + deadline_duration
		while Time.now < deadline
			if yield
				return
			else
				sleep(check_interval)
			end
		end
		raise "Time limit exceeded"
	end
end

# A thread which doesn't execute its block until the
# 'go!' method has been called.
class WaitingThread < Thread
	def initialize
		@mutex = Mutex.new
		@cond = ConditionVariable.new
		@go = false
		super do
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
