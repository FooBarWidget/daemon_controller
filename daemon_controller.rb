# Basic functionality for a single, local, external daemon:
# - starting daemon
#   * must be concurrency-safe!
#   * must be able to report startup errors!
#   * returns when daemon is fully operational
# - stopping daemon
#   * must be concurrency-safe!
#   * returns when daemon has exited
# - querying the status of a daemon
#   * querying the status of a daemon (i.e. whether it's running)
# - connect to a daemon, and start it if it isn't already running
#   * must be a single atomic action

require 'digest/md5'

class DaemonController
	class StartError < StandardError
	end
	class AlreadyStarted < StartError
	end
	class StartTimeout < StartError
	end

	# pid_file *must* be readable and writable
	# log_file *must* be readable
	def initialize(options)
		[:identifier, :start_command, :ping_command, :pid_file, :log_file].each do |option|
			if !options.has_key?(option)
				raise ArgumentError, "The ':#{option}' option is mandatory."
			end
		end
		@identifier = options[:identifier]
		@start_command = options[:start_command]
		@stop_command = options[:stop_command]
		@ping_command = options[:ping_command]
		@ping_interval = options[:ping_interval] || 0.1
		@pid_file = options[:pid_file]
		@log_file = options[:log_file]
		@start_timeout = options[:start_timeout] || 5
		@lock_file = determine_lock_file(@identifier, @pid_file)
	end
	
	def start
		exclusive_lock do
			if daemon_is_running?
				raise AlreadyStarted, "Daemon '#{@identifier}' is already started"
			end
			difference, result = monitor_differences_in_log_file do
				delete_pid_file
				spawn_daemon
				begin
					started = false
					Timeout.timeout(@start_timeout) do
						done = false
						wait_until_pid_file_is_available
						started = wait_until_daemon_responds_to_ping_or_has_exited
					end
					started
				rescue Timeout::Error
					:timeout
				end
			end
			if !result
				raise StartError, difference
			elsif result == :timeout
				raise StartTimeout, difference
			else
				return true
			end
		end
	end
	
	def connect
		connect_error = nil
		begin
			# We connect inside a shared lock so that we cannot connect to
			# the daemon while #start is still working.
			shared_lock do
				connection = yield
			end
		rescue => e
			connect_error = e
			connection = nil
		end
		if connection.nil?
			exclusive_lock do
				if daemon_is_running?
					connection = yield
					if connection.nil?
						# Daemon is running but we couldn't connect to it. Possible
						# reasons:
						# - The daemon froze.
						# - Bizarre security restrictions.
						# - There's a bug in the yielded code.
						if connect_error.is_a?(Errno::ECONNREFUSED)
							raise "?"
						else
							raise connect_error
						end
					else
						return connection
					end
				else
					start
					return yield
				end
			end
		else
			return connection
		end
	end
	
	def stop
		exclusive_lock do
			kill_daemon
		end
	end
	
	# Returns the daemon's PID, as reported by its PID file.
	# This method doesn't check whether the daemon's actually running.
	# Use #running? if you want to check whether it's actually running.
	#
	# Raises SystemCallError or IOError if something went wrong during
	# reading of the PID file.
	def pid
		shared_lock do
			return read_pid_file
		end
	end
	
	# Checks whether the daemon is still running. This is done by reading
	# the PID file and then checking whether there is a process with that
	# PID.
	#
	# Raises SystemCallError or IOError if something went wrong during
	# reading of the PID file.
	def running?
		shared_lock do
			return daemon_is_running?
		end
	end

private
	def exclusive_lock
		yield
	end
	
	def shared_lock
		yield
	end
	
	def spawn_daemon
		run_command(@start_command)
	end
	
	def kill_daemon
		if @stop_command
			run_command(@stop_command)
		else
			Process.kill('SIGTERM', read_pid_file)
		end
	end
	
	def daemon_is_running?
		begin
			pid = read_pid_file
		rescue Errno::EEXIST
			# The PID file may not exist, or another thread/process
			# executing #running? may have just deleted the PID file.
			# So we catch this error.
			pid = nil
		end
		if pid.nil?
			return false
		elsif check_pid(pid)
			return true
		else
			delete_pid_file
			return false
		end
	end
	
	def read_pid_file
		return File.read(@pid_file).strip.to_i
	end
	
	def delete_pid_file
		File.unlink(@pid_file)
	rescue Errno::EPERM, Errno::EACCES, Errno::ENOENT # ignore
	end
	
	def check_pid(pid)
		Process.kill(0, pid)
		return true
	rescue Errno::ESRCH
		return false
	rescue Errno::EPERM
		# We didn't have permission to kill the process. Either the process
		# is owned by someone else, or the system has draconian security
		# settings and we aren't allowed to kill *any* process. Assume that
		# the process is running.
		return true
	end
	
	def wait_until_pid_file_is_available
		done = false
		while !done
			if File.exist?(@pid_file) && File.stat(@pid_file).size != 0
				done = true
			else
				sleep 0.1
			end
		end
	end
	
	def wait_until_daemon_responds_to_ping_or_has_exited
		pinged = exited = false
		while !pinged && !exited
			pinged = run_ping_command
			exited = !pinged && !daemon_is_running?
			if !pinged && !exited
				sleep(@ping_interval)
			end
		end
		puts "result = #{pinged}, #{exited}"
		return pinged
	end
	
	def monitor_differences_in_log_file
		return ["", yield]
	end
	
	def determine_lock_file(identifier, pid_file)
		hash = Digest::MD5.hexdigest(identifier)
		return File.expand_path(File.join(File.dirname(pid_file), "daemon.#{hash}.lock"))
	end
	
	def run_command(command)
		pid = safe_fork do
			if command.respond_to?(:call)
				command.call
			else
				exec(command)
			end
		end
		begin
			Process.waitpid(pid) rescue nil
		rescue Timeout::Error
			Process.kill('SIGTERM', pid) rescue nil
			begin
				Timeout.timeout(5) do
					Process.waitpid(pid) rescue nil
				end
			rescue Timeout::Error
				Process.kill('SIGKILL', pid)
				Process.waitpid(pid) rescue nil
			end
			raise
		end
	end
	
	def run_ping_command
		if @ping_command.respond_to?(:call)
			return @ping_command.call
		else
			return system(@ping_command)
		end
	end
	
	def safe_fork
		pid = fork
		if pid.nil?
			begin
				yield
			rescue Exception => e
				message = "*** Exception #{e.class} " <<
					"(#{e}) (process #{$$}):\n" <<
					"\tfrom " << e.backtrace.join("\n\tfrom ")
				STDERR.write(e)
				STDERR.flush
			ensure
				exit!
			end
		else
			return pid
		end
	end
end
