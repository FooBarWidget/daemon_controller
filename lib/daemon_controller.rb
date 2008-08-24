# daemon_controller, library for robust daemon management
# Copyright (c) 2008 Phusion
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'tempfile'
require 'fcntl'
require File.expand_path(File.dirname(__FILE__) << '/daemon_controller/lock_file')

# Main daemon controller object. See the README for an introduction and tutorial.
class DaemonController
	ALLOWED_CONNECT_EXCEPTIONS = [Errno::ECONNREFUSED, Errno::ENETUNREACH,
		Errno::ETIMEDOUT, Errno::ECONNRESET]
	
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

	# Create a new DaemonController object.
	#
	# === Mandatory options
	#
	# [:identifier]
	#  A human-readable, unique name for this daemon, e.g. "Sphinx search server".
	#  This identifier will be used in some error messages. On some platforms, it will
	#  be used for concurrency control: on such platforms, no two DaemonController
	#  objects will operate on the same identifier on the same time.
	#  
	# [:start_command]
	#  The command to start the daemon. This must be a a String, e.g.
	#  "mongrel_rails start -e production".
	#  
	# [:ping_command]
	#  The ping command is used to check whether the daemon can be connected to.
	#  It is also used to ensure that #start only returns when the daemon can be
	#  connected to.
	#  
	#  The value may be a command string. This command must exit with an exit code of
	#  0 if the daemon can be successfully connected to, or exit with a non-0 exit
	#  code on failure.
	#  
	#  The value may also be a Proc, which returns an expression that evaluates to
	#  true (indicating that the daemon can be connected to) or false (failure).
	#  If the Proc raises Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::ETIMEDOUT
	#  or Errno::ECONNRESET, then that also means that the daemon cannot be connected
	#  to.
	#  <b>NOTE:</b> if the ping command returns an object which responds to
	#  <tt>#close</tt>, then that method will be called on the return value.
	#  This makes it possible to specify a ping command such as
	#  <tt>lambda { TCPSocket.new('localhost', 1234) }</tt>, without having to worry
	#  about closing it afterwards.
	#  Any exceptions raised by #close are ignored.
	#  
	# [:pid_file]
	#  The PID file that the daemon will write to. Used to check whether the daemon
	#  is running.
	#  
	# [:log_file]
	#  The log file that the daemon will write to. It will be consulted to see
	#  whether the daemon has printed any error messages during startup.
	#
	# === Optional options
	# [:stop_command]
	#  A command to stop the daemon with, e.g. "/etc/rc.d/nginx stop". If no stop
	#  command is given (i.e. +nil+), then DaemonController will stop the daemon
	#  by killing the PID written in the PID file.
	#  
	#  The default value is +nil+.
	#
	# [:before_start]
	#  This may be a Proc. It will be called just before running the start command.
	#  The before_start proc is not subject to the start timeout.
	#  
	# [:start_timeout]
	#  The maximum amount of time, in seconds, that #start may take to start
	#  the daemon. Since #start also waits until the daemon can be connected to,
	#  that wait time is counted as well. If the daemon does not start in time,
	#  then #start will raise an exception.
	#  
	#  The default value is 15.
	#  
	# [:stop_timeout]
	#  The maximum amount of time, in seconds, that #stop may take to stop
	#  the daemon. Since #stop also waits until the daemon is no longer running,
	#  that wait time is counted as well. If the daemon does not stop in time,
	#  then #stop will raise an exception.
	#  
	#  The default value is 15.
	#  
	# [:log_file_activity_timeout]
	#  Once a daemon has gone into the background, it will become difficult to
	#  know for certain whether it is still initializing or whether it has
	#  failed and exited, until it has written its PID file. It's 99.9% probable
	#  that the daemon has terminated with an if its start timeout has expired,
	#  not many system administrators want to wait 15 seconds (the default start
	#  timeout) to be notified of whether the daemon has terminated with an error.
	#  
	#  An alternative way to check whether the daemon has terminated with an error,
	#  is by checking whether its log file has been recently updated. If, after the
	#  daemon has started, the log file hasn't been updated for the amount of seconds
	#  given by the :log_file_activity_timeout option, then the daemon is assumed to
	#  have terminated with an error.
	#  
	#  The default value is 7.
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
		@before_start = options[:before_start]
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
		@lock_file.exclusive_lock do
			start_without_locking
		end
	end
	
	# Connect to the daemon by running the given block, which contains the
	# connection logic. If the daemon isn't already running, then it will be
	# started.
	#
	# The block must return nil or raise Errno::ECONNREFUSED, Errno::ENETUNREACH,
	# Errno::ETIMEDOUT, Errno::ECONNRESET to indicate that the daemon cannot be
	# connected to. It must return non-nil if the daemon can be connected to.
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
		@lock_file.shared_lock do
			begin
				connection = yield
			rescue *ALLOWED_CONNECT_EXCEPTIONS
				connection = nil
			end
		end
		if connection.nil?
			@lock_file.exclusive_lock do
				if !daemon_is_running?
					start_without_locking
				end
				begin
					connection = yield
				rescue *ALLOWED_CONNECT_EXCEPTIONS
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
		@lock_file.exclusive_lock do
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
	
	# Returns the daemon's PID, as reported by its PID file. Returns the PID
	# as an integer, or nil there is no valid PID in the PID file.
	#
	# This method doesn't check whether the daemon's actually running.
	# Use #running? if you want to check whether it's actually running.
	#
	# Raises SystemCallError or IOError if something went wrong during
	# reading of the PID file.
	def pid
		@lock_file.shared_lock do
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
		@lock_file.shared_lock do
			return daemon_is_running?
		end
	end

private
	def start_without_locking
		if daemon_is_running?
			raise AlreadyStarted, "Daemon '#{@identifier}' is already started"
		end
		save_log_file_information
		delete_pid_file
		begin
			started = false
			before_start
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
			raise(StartError, differences_in_log_file ||
				"Daemon '#{@identifier}' failed to start.")
		elsif result == :timeout
			raise(StartTimeout, differences_in_log_file ||
				"Daemon '#{@identifier}' failed to start in time.")
		else
			return true
		end
	end
	
	def before_start
		if @before_start
			@before_start.call
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
		pid = read_pid_file
		if pid
			Process.kill('SIGTERM', pid)
		end
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
		pid = File.read(@pid_file).strip
		if pid =~ /\A\d+\Z/
			return pid.to_i
		else
			return nil
		end
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
				diff = f.read.strip
				if diff.empty?
					return nil
				else
					return diff
				end
			end
		else
			return nil
		end
	rescue Errno::ENOENT
		return nil
	end
	
	def determine_lock_file(identifier, pid_file)
		return LockFile.new(File.expand_path(pid_file + ".lock"))
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
			begin
				value = @ping_command.call
				if value.respond_to?(:close)
					value.close rescue nil
				end
				return value
			rescue *ALLOWED_CONNECT_EXCEPTIONS
				return false
			end
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
