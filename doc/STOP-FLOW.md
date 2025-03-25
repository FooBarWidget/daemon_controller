# Stop flow

## Regular stop flow

This flow is triggered upon `#stop` calling stop.

1. Graceful termination request: either run the stop command, or send `stop_graceful_signal` to the PID. Then wait until daemon is gone.
   - Stop command is only invoked, or signal is only sent, if the PID file is valid or `dont_stop_if_pid_file_invalid` is true.
2. Force termination upon timeout (`stop_timeout`): send SIGKILL to the PID. Then wait until daemon is gone, then delete the PID file.
   - No timeout here: we assume the OS processes it quickly enough.

## Start timeout stop flow

This flow is triggered when `#stop` times out.

1. Graceful termination request: send SIGTERM to the PID and wait until it's gone.
   - No possibility to customize signal here. Rationale: this is an abnormal stop so we don't use the stop command.
2. Force termination upon timeout (`start_abort_timeout`) of step 1: send SIGKILL to the PID and wait until it's gone.
   - No timeout here: we assume the OS processes a SIGKILL quickly enough.
