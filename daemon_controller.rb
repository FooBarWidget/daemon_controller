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

require 'tempfile'
require 'fcntl'

class DaemonController
	class Error < StandardError
	end
	class TimeoutError < Error
	end
	class AlreadyStarted < Error
	end
	class StartError < Error
	end
	class StartTimeout < TimeoutError
	end
	class StopError < Error
	end
	class StopTimeout < TimeoutError
	end
	class ConnectError < Error
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
		@start_timeout = options[:start_timeout] || 15
		@stop_timeout = options[:stop_timeout] || 15
		@log_file_activity_timeout = options[:log_file_activity_timeout] || 7
		@lock_file = determine_lock_file(@identifier, @pid_file)
	end
	
	# Start the daemon and wait until it can be pinged.
	#
	# Raises:
	# - AlreadyStarted - the daemon is already running.
	# - StartError - the start command failed.
	# - StartTimeout - the daemon did not start in time. This could also
	#   mean that the daemon failed after it has gone into the background.
	def start
		exclusive_lock do
			start_without_locking
		end
	end
	
	# Connect to the daemon by running the given block, which contains the
	# connection logic. If the daemon isn't already running, then it will be
	# started.
	#
	# The block must return nil or raise Errno::ECONNREFUSED, Errno::ENETUNREACH,
	# or Errno::ETIMEDOUT to indicate that the daemon cannot be connected to.
	# It must return non-nil if the daemon can be connected to.
	# Upon successful connection, the return value of the block will
	# be returned by #connect.
	#
	# Note that the block may be called multiple times.
	#
	# Raises:
	# - StartError - an attempt to start the daemon was made, but the start
	#   command failed with an error.
	# - StartTimeout - an attempt to start the daemon was made, but the daemon
	#   did not start in time, or it failed after it has gone into the background.
	# - ConnectError - the daemon wasn't already running, but we couldn't connect
	#   to the daemon even after starting it.
	def connect
		connection = nil
		shared_lock do
			begin
				connection = yield
			rescue Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::ETIMEDOUT
				connection = nil
			end
		end
		if connection.nil?
			exclusive_lock do
				if !daemon_is_running?
					start_without_locking
				end
				begin
					connection = yield
				rescue Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::ETIMEDOUT
					connection = nil
				end
				if connection.nil?
					# Daemon is running but we couldn't connect to it. Possible
					# reasons:
					# - The daemon froze.
					# - Bizarre security restrictions.
					# - There's a bug in the yielded code.
					raise ConnectError, "Cannot connect to the daemon"
				else
					return connection
				end
			end
		else
			return connection
		end
	end
	
	# Stop the daemon and wait until it has exited.
	#
	# Raises:
	# - StopError - the stop command failed.
	# - StopTimeout - the daemon didn't stop in time.
	def stop
		exclusive_lock do
			begin
				Timeout.timeout(@stop_timeout) do
					kill_daemon
					wait_until do
						!daemon_is_running?
					end
				end
			rescue Timeout::Error
				raise StopTimeout, "Daemon '#{@identifier}' did not exit in time"
			end
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
		File.open(@lock_file, 'w') do |f|
			if Fcntl.const_defined? :F_SETFD
				f.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
			end
			f.flock(File::LOCK_EX)
			yield
		end
	end
	
	def shared_lock
		File.open(@lock_file, 'w') do |f|
			if Fcntl.const_defined? :F_SETFD
				f.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
			end
			f.flock(File::LOCK_SH)
			yield
		end
	end
	
	def start_without_locking
		if daemon_is_running?
			raise AlreadyStarted, "Daemon '#{@identifier}' is already started"
		end
		save_log_file_information
		delete_pid_file
		begin
			started = false
			Timeout.timeout(@start_timeout) do
				done = false
				spawn_daemon
				record_activity
				
				# We wait until the PID file is available and until
				# the daemon responds to pings, but we wait no longer
				# than @start_timeout seconds in total (including daemon
				# spawn time).
				# Furthermore, if the log file hasn't changed for
				# @log_file_activity_timeout seconds, and the PID file
				# still isn't available or the daemon still doesn't
				# respond to pings, then assume that the daemon has
				# terminated with an error.
				wait_until do
					if log_file_has_changed?
						record_activity
					elsif no_activity?(@log_file_activity_timeout)
						raise Timeout::Error, "Daemon seems to have exited"
					end
					pid_file_available?
				end
				wait_until(@ping_interval) do
					if log_file_has_changed?
						record_activity
					elsif no_activity?(@log_file_activity_timeout)
						raise Timeout::Error, "Daemon seems to have exited"
					end
					run_ping_command || !daemon_is_running?
				end
				started = run_ping_command
			end
			result = started
		rescue Timeout::Error
			start_timed_out
			if pid_file_available?
				kill_daemon_with_signal
			end
			result = :timeout
		end
		if !result
			raise StartError, differences_in_log_file
		elsif result == :timeout
			raise StartTimeout, differences_in_log_file
		else
			return true
		end
	end
	
	def spawn_daemon
		run_command(@start_command)
	end
	
	def kill_daemon
		if @stop_command
			begin
				run_command(@stop_command)
			rescue StartError => e
				raise StopError, e.message
			end
		else
			kill_daemon_with_signal
		end
	end
	
	def kill_daemon_with_signal
		Process.kill('SIGTERM', read_pid_file)
	rescue Errno::ESRCH, Errno::ENOENT
	end
	
	def daemon_is_running?
		begin
			pid = read_pid_file
		rescue Errno::ENOENT
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
	
	def wait_until(sleep_interval = 0.1)
		while !yield
			sleep(sleep_interval)
		end
	end
	
	def wait_until_pid_file_is_available_or_log_file_has_changed
		while !(pid_file_available? || log_file_has_changed?)
			sleep 0.1
		end
		return pid_file_is_available?
	end
	
	def wait_until_daemon_responds_to_ping_or_has_exited_or_log_file_has_changed
		while !(run_ping_command || !daemon_is_running? || log_file_has_changed?)
			sleep(@ping_interval)
		end
		return run_ping_command
	end
	
	def record_activity
		@last_activity_time = Time.now
	end
	
	# Check whether there has been no recorded activity in the past +seconds+ seconds.
	def no_activity?(seconds)
		return Time.now - @last_activity_time > seconds
	end
	
	def pid_file_available?
		return File.exist?(@pid_file) && File.stat(@pid_file).size != 0
	end
	
	# This method does nothing and only serves as a hook for the unit test.
	def start_timed_out
	end
	
	def save_log_file_information
		@original_log_file_stat = File.stat(@log_file) rescue nil
		@current_log_file_stat = @original_log_file_stat
	end
	
	def log_file_has_changed?
		if @current_log_file_stat
			stat = File.stat(@log_file) rescue nil
			if stat
				result = @current_log_file_stat.mtime != stat.mtime ||
				         @current_log_file_stat.size  != stat.size
				@current_log_file_stat = stat
				return result
			else
				return true
			end
		else
			return false
		end
	end
	
	def differences_in_log_file
		if @original_log_file_stat
			File.open(@log_file, 'r') do |f|
				f.seek(@original_log_file_stat.size, IO::SEEK_SET)
				return f.read.strip
			end
		else
			return nil
		end
	rescue Errno::ENOENT
		return nil
	end
	
	def determine_lock_file(identifier, pid_file)
		return File.expand_path(pid_file + ".lock")
	end
	
	def self.fork_supported?
		return RUBY_PLATFORM != "java" && RUBY_PLATFORM !~ /win32/
	end
	
	def run_command(command)
		# Create tempfile for storing the command's output.
		tempfile = Tempfile.new('daemon-output')
		tempfile_path = tempfile.path
		File.chmod(0666, tempfile_path)
		tempfile.close
		
		if self.class.fork_supported?
			pid = safe_fork do
				STDIN.reopen("/dev/null", "r")
				STDOUT.reopen(tempfile_path, "w")
				STDERR.reopen(tempfile_path, "w")
				exec(command)
			end
			begin
				Process.waitpid(pid) rescue nil
			rescue Timeout::Error
				# If the daemon doesn't fork into the background
				# in time, then kill it.
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
			if $?.exitstatus != 0
				raise StartError, File.read(tempfile_path).strip
			end
		else
			if !system("#{command} >\"#{tempfile_path}\" 2>\"#{tempfile_path}\"")
				raise StartError, File.read(tempfile_path).strip
			end
		end
	ensure
		File.unlink(tempfile_path) rescue nil
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
