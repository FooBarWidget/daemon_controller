# Configuration options

Options accepted by constructor.

## Mandatory options

### identifier

Human-readable, unique name for this daemon, e.g. "Sphinx search server".
This identifier will be used in some error messages. On some platforms, it will
be used for concurrency control: on such platforms, no two DaemonController
objects will operate on the same identifier on the same time.

### start_command

Command to start the daemon. This must be a a String, e.g.
"mongrel_rails start -e production", or a Proc which returns a String.

If the value is a Proc, and the `before_start` option is given too, then
the `start_command` Proc is guaranteed to be called after the `before_start`
Proc is called.

This is subject to a timeout, see `start_timeout` and [Stop flow](STOP_FLOW.md).

### ping_command

Command used to check whether the daemon can be connected to.
It is also used to ensure that #start only returns when the daemon can be
connected to.

Value may be a command string. This command must exit with an exit code of
0 if the daemon can be successfully connected to, or exit with a non-0 exit
code on failure.

Value may also be an Array which specifies the socket address of the daemon.
It must be in one of the following forms:
- `[:tcp, host_name, port]`
- `[:unix, filename]`

Value may also be a Proc, which returns an expression that evaluates to
true (indicating that the daemon can be connected to) or false (failure).
If the Proc raises Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::ETIMEDOUT
Errno::ECONNRESET, Errno::EINVAL or Errno::EADDRNOTAVAIL then that also
means that the daemon cannot be connected to.
**NOTE:** if the ping command returns an object which responds to
`#close`, then that method will be called on it.
This makes it possible to specify a ping command such as
`lambda { TCPSocket.new('localhost', 1234) }`, without having to worry
about closing it afterwards.
Any exceptions raised by #close are ignored.

### pid_file

PID file that the daemon will write to. Used to check whether the daemon
is running.

### log_file

Log file that the daemon will write to. It will be consulted to see
whether the daemon has printed any error messages during startup.


## Optional options

### lock_file (default: "(filename of PID file).lock")

Lock file to use for serializing concurrent daemon management operations.

### stop_command (default: nil)

Command to stop the daemon with, e.g. "/etc/rc.d/nginx stop".

If no stop command is given (i.e., `nil`), then will stop the daemon
by sending signals to the PID written in the PID file.

### restart_command (default: nil)

Command to restart the daemon with, e.g. "/etc/rc.d/nginx restart". If
no restart command is given (i.e. `nil`), then DaemonController will
restart the daemon by calling #stop and #start.

### before_start (default: nil)

This may be a Proc. It will be called just before running the start command.
The Proc call is not subject to the start timeout.

### start_timeout (default: 30)

Maximum amount of time (seconds) that #start may take to start
the daemon. Since #start also waits until the daemon can be connected to,
that wait time is counted as well. If the daemon does not start in time,
then #start will raise an exception and also stop the daemon.

### stop_timeout (default: 30)

Maximum amount of time (seconds) that #stop may take to stop
the daemon. Since #stop also waits until the daemon is no longer running,
that wait time is counted as well. If the daemon does not stop in time,
then #stop will raise an exception and force stop the daemon.

### log_file_activity_timeout (default: 10)

Once a daemon has gone into the background, it will become difficult to
know for certain whether it is still initializing or whether it has
failed and exited, until it has written its PID file. Suppose that it
failed with an error after daemonizing but before it has written its PID file;
not many system administrators want to wait 30 seconds (the default start
timeout) to be notified of whether the daemon has terminated with an error.

An alternative way to check whether the daemon has terminated with an error,
is by checking whether its log file has been recently updated. If, after the
daemon has started, the log file hasn't been updated for the amount of seconds
given by this option, then the daemon is assumed to have terminated with an error.

### ping_interval (default: 0.1)

Time interval (seconds) between pinging attempts (see `ping_command`) when waiting
for the daemon to start.

### dont_stop_if_pid_file_invalid (default: false)

If the stop_command option is given, then normally daemon_controller will
always execute this command upon calling #stop. But if dont_stop_if_pid_file_invalid
is given, then daemon_controller will not do that if the PID file does not contain
a valid number.

### daemonize_for_me (default: false)

Normally daemon_controller will wait until the daemon has daemonized into the
background, in order to capture any errors that it may print on stdout or
stderr before daemonizing. However, if the daemon doesn't support daemonization
for some reason, then setting this option to true will cause daemon_controller
to do the daemonization for the daemon.

### keep_ios (default: nil)

Upon spawning the daemon, daemon_controller will normally close all file
descriptors except stdin, stdout and stderr. However if there are any file
descriptors you want to keep open, specify the IO objects here. This must be
an array of IO objects.

### env (default: nil)

This must be a Hash. The hash will contain the environment variables available
to be made available to the daemon. Hash keys must be Strings, not Symbols.
