Introduction
============

*daemon_controller* is a library for starting and stopping specific daemons
programmatically in a robust, race-condition-free manner.

It's not a daemon monitoring system like God or Monit. It's also not a library
for writing daemons.

It provides the following functionality:

*   Starting daemons. If the daemon fails to start then an exception will be
    raised. *daemon_controller* can even detect failures that occur after the
    daemon has already daemonized.
    
    Starting daemons is done in a race-condition-free manner. If another
    process using *daemon_controller* is trying to start the same daemon,
    then *daemon_controller* will guarantee serialization.
    
    *daemon_controller* also raises an exception if it detects that the daemon
    is already started.
*   Connecting to a daemon, starting it if it's not already started. This too
    is done in a race-condition-free manner. If the daemon fails to start then
    an exception will be raised.
*   Stopping daemons.
*   Checking whether a daemon is running.

## Installation with RubyGems

    gem install daemon_controller

This gem is signed using PGP with the [Phusion Software Signing key](http://www.phusion.nl/about/gpg). That key in turn is signed by [the rubygems-openpgp Certificate Authority](http://www.rubygems-openpgp-ca.org/).

You can verify the authenticity of the gem by following [The Complete Guide to Verifying Gems with rubygems-openpgp](http://www.rubygems-openpgp-ca.org/blog/the-complete-guide-to-verifying-gems-with-rubygems-openpgp.html).

## Installation on Ubuntu

Use our [PPA](https://launchpad.net/~phusion.nl/+archive/misc):

    sudo add-apt-repository ppa:phusion.nl/misc
    sudo apt-get update
    sudo apt-get install ruby-daemon-controller

## Installation on Debian

Our Ubuntu Lucid packages are compatible with Debian 6.

    sudo sh -c 'echo deb http://ppa.launchpad.net/phusion.nl/misc/ubuntu lucid main > /etc/apt/sources.list.d/phusion-misc.list'
    sudo sh -c 'echo deb-src http://ppa.launchpad.net/phusion.nl/misc/ubuntu lucid main >> /etc/apt/sources.list.d/phusion-misc.list'
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 2AC745A50A212A8C
    sudo apt-get update
    sudo apt-get install ruby-daemon-controller

## Installation on RHEL, CentOS and Amazon Linux

Enable our YUM repository:

    # RHEL 6, CentOS 6
    curl -L https://oss-binaries.phusionpassenger.com/yumgems/phusion-misc/el.repo | \
      sudo tee /etc/yum.repos.d/phusion-misc.repo
    
    # Amazon Linux
    curl -L https://oss-binaries.phusionpassenger.com/yumgems/phusion-misc/amazon.repo | \
      sudo tee /etc/yum.repos.d/phusion-misc.repo

Install our package:

    sudo yum install rubygem-daemon_controller

## Resources

*   [Website](https://github.com/FooBarWidget/daemon_controller)
*   [RDoc](http://rdoc.info/projects/FooBarWidget/daemon_controller)
*   [Git repository](git://github.com/FooBarWidget/daemon_controller.git)


What is it for?
===============

There is a lot of software (both Rails related and unrelated) which rely on
servers or daemons. To name a few, in no particular order:

 * [Ultrasphinx](http://blog.evanweaver.com/files/doc/fauna/ultrasphinx/), a
   Rails library for full-text searching. It makes use the [Sphinx search
   software](http://www.sphinxsearch.com/) for indexing and searching. Indexing
   is done by running a command, while searching is done by querying the Sphinx
   search server.
 * [acts_as_ferret](http://projects.jkraemer.net/acts_as_ferret/wiki), another
   Rails library for full-text searching. It uses the Ferret search software.
   On production environments, it relies on the Ferret DRB server for both
   searching and indexing.
 * [BackgrounDRb](http://backgroundrb.rubyforge.org/), a Ruby job server and
   scheduler. Scheduling is done by contacting the BackgrounDRb daemon.
 * [mongrel_cluster](http://mongrel.rubyforge.org/wiki/MongrelCluster), which
   starts and stops multiple Mongrel daemons.

Relying on daemons is quite common, but not without problems. Let's go over
some of them.

### Starting daemons is a hassle

If you've used similar software, then you might agree that managing these
daemons is a hassle. If you're using BackgrounDRb, then the daemon must be
running. Starting the daemon is not hard, but it is annoying. It's also
possible that the system administrator forgets to start the daemon. While
configuring the system to automatically start a daemon at startup is not hard,
it is an extra thing to do, and thus a hassle. We thought, why can't such
daemons be automatically started? Indeed, this won't be possible if the daemon
is to be run on a remote machine. But in by far the majority of use cases, the
daemon runs on the same host as the Rails application. If a Rails application -
or indeed, <em>any</em> application - is configured to contact a daemon on the
local host, then why not start the daemon automatically on demand?

### Daemon starting code may not be robust or efficient

We've also observed that people write daemon controlling code over and over
again. Consider for example UltraSphinx, which provides a
`rake sphinx:daemon:start` Rake task to start the daemon. The time that a
daemon needs to initialize is variable, and depends on things such as the
current system load. The Sphinx daemon usually needs less than a second before
we can connect to it. However, the way different software handles starting of a
daemon varies. We've observed that waiting a fixed amount of time is by far the
most common way. For example, UltraSphinx's daemon starting code looks like
this:

    system "searchd --config '#{Ultrasphinx::CONF_PATH}'"
    sleep(4) # give daemon a chance to write the pid file
    if ultrasphinx_daemon_running?
       say "started successfully"
    else
       say "failed to start"
    end

This is in no way a slam against UltraSphinx. However, if the daemon starts in
200 miliseconds, then the user who issued the start command will be waiting for
3.8 seconds for no good reason. This is not good for usability or for the
user's patience.

### Startup error handling

Different software handles daemon startup errors in different ways. Some might
not even handle errors at all. For example, consider 'mongrel_cluster'. If
there's a typo in one of your application source files, then 'mongrel_cluster'
will not report the error. Instead, you have to check its log files to see what
happened. This is not good for usability: many people will be wondering why
they can't connect to their Mongrel ports after issuing a
`mongrel_rails cluster::start` - until they realize that they should read the
log file. But the thing is, not everybody realizes this. And typing in an extra
command to read the log file to check whether Mongrel started correctly, is
just a big hassle. Why can't the daemon startup code report such errors
immediately?

### Stale or corrupt Pid files

Suppose that you're running a Mongrel cluster, and your server suddenly powers
off because of a power outage. When the server is online again, it fails to
start your Mongrel cluster because the PID file that it had written still
exists, and wasn't cleaned up properly (it's supposed to be cleaned up when
Mongrel exits). mongrel_cluster provides the `--clean` option to check whether
the PID file is *stale*, and will automatically clean it up if it is. But not
all daemon controlling software supports this. Why can't all software check for
stale PID files automatically?


## Implementation issues

From the problem descriptions, it would become apparent that our wishlist is as
follows. Why is this wishlist often not implemented? Let's go over them.

 -  **A daemon should be automatically started on demand, instead of requiring the user to manually start it.**
    
    The most obvious problems are related to concurrency. Suppose that your web
    application has a search box, and you want to start the search daemon if it
    isn't already started, then connect to. Two problems will arise:
    
     *  Suppose that Rails process A is still starting the daemon. At the same
        time, another visitor tries to search something, and Rails process B
        notices that the daemon is not running. If B tries to start the daemon
        while it's already being started by A, then things can go wrong.
        *A robust daemon starter must ensure that only one process at the same time may start the daemon.*
     *  It's not a good idea to wait a fixed amount of time for the daemon to
        start, because you don't know in advance how long it will take for it to
        start. For example, if you wait 2 seconds, then try to connect to the
        daemon, and the daemon isn't done initializing yet, then it will seem as
        if the daemon failed to start.
    
    These are the most probable reasons why people don't try to write
    auto-starting code, and instead require the user to start the daemon
    manually.
    
    These problems, as well as several less obvious problems, are closely
    related to the next few points.
    
 -  **The daemon starter must wait until the daemon is done initializing, no longer and no shorter**
    
    Because only after the daemon is fully initialized, is it safe to connect
    to it. And because the user should not have to wait longer than he really
    has to. During startup, the daemon will have to be continuously checked
    whether it's done initializing or whether an error occured. Writing this
    code can be quite a hassle, which is why most people don't do it.
    
 -  **The daemon starter must report any startup errors**
    
    If the daemon starting command - e.g. `sphinx -c config_file.conf`,
    `apachectl start` or `mongrel_rails cluster::start` - reports startup
    errors, then all is fine as long as the user is starting the command from a
    terminal. A problem occurs when the error occurs after the daemon has
    already gone into the background. Such errors are only reported to the log
    file.
    *The daemon starter should also check the log file for any startup errors.*
    
    Furthermore, it should be able to raise startup errors as exceptions. This
    allows the the application to decide what to do with the error. For less
    experienced system administrators, the error might be displayed in the
    browser, allowing the administrators to become aware of the problem without
    forcing them to manually check the log files. Or the error might be emailed
    to a system administrator's email address.
    
 -  **The daemon starter must be able to correct stale or corrupted PID files**
    
    If the PID file is stale, or for some reason has been corrupted, then the
    daemon starter must be able to cope with that.
    *It should check whether the PID file contains a valid PID, and whether the PID exists.*


Introducing daemon_controller
=============================

*daemon_controller* is a library for managing daemons in a robust manner. It is
not a tool for managing daemons. Rather, it is a library which lets you write
applications that manage daemons in a robust manner. For example,
'mongrel_cluster' or UltraSphinx may be adapted to utilize this library, for
more robust daemon management.

*daemon_controller* implements all items in the aforementioned wishlist. It
provides the following functionalities:

### Starting a daemon

This ensures that no two processes can start the same daemon at the same time.
It will also reports any startup errors, even errors that occur after the
daemon has already gone into the background but before it has fully initialized
yet. It also allows you to set a timeout, and will try to abort the daemon if
it takes too long to initialize.

The start function won't return until the daemon has been fully initialized,
and is responding to connections. So if the start function has returned, then
the daemon is guaranteed to be usable.

### Stopping a daemon

It will stop the daemon, but only if it's already running. Any errors
are reported. If the daemon isn't already running, then it will silently
succeed. Just like starting a daemon, you can set a timeout for stopping the
daemon.

Like the start function, the stop function won't return until the daemon is no
longer running. This makes it save to immediately start the same daemon again
after having stopped it, without worrying that the previous daemon instance
hasn't exited yet and might conflict with the newly started daemon instance.

### Connecting to a daemon, starting it if it isn't running

Every daemon has to be connected to using a different way. As a developer, you
tell 'daemon_controller' how to connect to the daemon. It will then attempt to
do that, and if that fails, it will check whether the daemon is running. If it
isn't running, then it will automatically start the daemon, and attempt to
connect to the daemon again. Failures are reported.

### Checking whether a daemon is running

This information is retrieved from the PID file. It also checks whether the PID
file is stale.

### All failures are reported via exceptions

So that you can exactly determine how you want to handle errors.

### Lots and lots of error checking

So that there are very few ways in which the system can screw up.

daemon_controller's goal is to make daemon management less of a hassle, and as
automatic and straightforward as possible.


What about Monit/God?
=====================

daemon_controller is not a replacement for [Monit](http://www.tildeslash.com/monit/)
or [God](http://god.rubyforge.org/). Rather, it is a solution to the following
problem:

> **Hongli:** hey Ninh, do a 'git pull', I just implemented awesome searching
>    features in our application!  
>   **Ninh:** cool. *pulls from repository*  
>   **Ninh:** hey Hongli, it doesn't work.  
> **Hongli:** what do you mean, it doesn't work?  
>   **Ninh:** it says "connection refused", or something  
> **Hongli:** oh I forgot to mention it, you have to run the Sphinx search
>    daemon before it works. type "rake sphinx:daemon:start" to do
>    that  
>   **Ninh:** great. but now I get a different error. something about
>    BackgrounDRb.  
> **Hongli:** oops, I forgot to mention this too. you need to start the
>    BackgrounDRb server with "rake backgroundrb:start_server"  
>   **Ninh:** okay, so every time I want to use this app, I have to type
>    "rake sphinx:daemon:start", "rake backgroundrb:start_server" and
>    "./script/server"?  
> **Hongli:** yep

Imagine the above conversation becoming just:

> **Hongli:** hey Ninh, do a 'git pull', I just implemented awesome searching
>    features in our application!  
>   **Ninh:** cool. *pulls from repository*  
>   **Ninh:** awesome, it works!

This is not something that can be achieved with Monit/God. Monit/God are for
monitoring daemons, auto-restarting them when they use too much resources.
daemon_controller's goal is to allow developers to implement daemon
starting/stopping and daemon auto-starting code that's robust. daemon_controller
is intended to be used to make daemon-dependent applications Just Work(tm)
without having to start the daemons manually.


Tutorial #1: controlling Apache
===============================

Suppose that you're a [Phusion Passenger](http://www.modrails.com/) developer,
and you need to write tests for the Apache module. In particular, you want to
test whether the different Phusion Passenger configuration directives are
working as expected. Obviously, to test the Apache module, the Apache web
server must be running. For every test, you will want the unit test suite to:

 1. Write an Apache configuration file, with the relevant configuration
    directive set to a specific value.
 2. Start Apache.
 3. Send an HTTP request to Apache and check whether the HTTP response matches
    your expectations.
 4. Stop Apache.

That can be done with the following code:

    require 'daemon_controller'
    
    File.open("apache.conf", "w") do |f|
       f.write("PidFile apache.pid\n")
       f.write("LogFile apache.log\n")
       f.write("Listen 1234\n")
       f.write(... other relevant configuration options ...)
    end
    
    controller = DaemonController.new(
       :identifier    => 'Apache web server',
       :start_command => 'apachectl -f apache.conf -k start',
       :ping_command  => [:tcp, 'localhost', 1234],
       :pid_file      => 'apache.pid',
       :log_file      => 'apache.log',
       :start_timeout => 25
    )
    controller.start
    
    .... apache is now started ....
    .... some test code here ....
    
    controller.stop

The `File.open` line is obvious: it writes the relevant Apache configuration
file.

The next line is for creating a new DaemonController object. We pass a
human-readable identifier for this daemon ("Apache web server") to the
constructor. This is used for generating friendlier error messages.
We also tell it how Apache is supposed to be started (`:start_command`), how to
check whether it can be connected to (`:ping_command`), and where its PID file
and log file is. If Apache failed with an error during startup, then it will be
reported. If Apache failed with an error after it has gone into the background,
then that will be reported too: the given log file is monitored for new error
messages.
Finally, a timeout of 25 seconds is given. If Apache doesn't start within 25
seconds, then an exception will be raised.

The ping command is just a `Proc` which returns true or false. If the Proc
raises `Errno::ECONNREFUSED`, then that's also interpreted by DaemonController
as meaning that the daemon isn't responding yet.

After `controller.start` has returned, we can continue with the test case. At
this point, we know that Apache is done with initializing.
When we're done with Apache, we stop it with `controller.stop`. This does not
return until Apache has fully stopped.

The cautious reader might notice that the socket returned by the ping command
is never closed. That's true, because DaemonController will close it
automatically for us, if it notices that the ping command proc's return value
responds to `#close`.

From this example, it becomes apparent that for daemon_controller to work, you
must know how to start the daemon, how to contact the daemon, and you must know
where it will put its PID file and log file.


Tutorial #2: Sphinx indexing and search server management
=========================================================

We at Phusion are currently developing a web application with full-text search
capabilities, and we're using Sphinx for this purpose. We want to make the
lives of our developers and our system administrators as easy as possible, so
that there's little room for human screw-up, and so we've developed this
library. Our Sphinx search daemon is completely managed through this library
and is automatically started on demand.

Our Sphinx config file is generated from an ERB template. This ERB template
writes different values in the config file, depending on whether we're in
development, test or production mode. We will want to regenerate this config
file every time, just before we start the search daemon.
But there's more. The search daemon will fail if there is no search index. If a
new developer has just checked out the application's source code, then there is
no search index yet. We don't want him to go through the pain of having to
generate the index manually. (That said, it isn't that much of a pain, but it's
just yet-another-thing to do, which can and should be automated.) So before
starting the daemon, we will also want to check whether the index exists. If
not, then we'll generate it, and then start the daemon. Of course, no two Rails
processes may generate the config file or the index at the same time.

When querying the search server, we will want to automatically start it if it
isn't running.

This can be achieved with the following code:

    require 'daemon_controller'
    
    class SearchServer
       SEARCH_SERVER_PORT = 1234
    
       def initialize
          @controller = DaemonController.new(
             :identifier => 'Sphinx search server',
             :start_command => "searchd -c config/sphinx.conf",
             :before_start => method(:before_start),
             :ping_command => [:tcp, 'localhost', SEARCH_SERVER_PORT],
             :pid_file => 'tmp/pids/sphinx.pid',
             :log_file => 'log/sphinx.log')
       end
       
       def query(search_terms)
          socket = @controller.connect do
             TCPSocket.new('localhost', SEARCH_SERVER_PORT)
          end
          send_query(socket, search_terms)
          return retrieve_results(socket)
       end
       
    private
       def before_start
          generate_configuration_file
          if !index_exists?
             generate_index
          end
       end
       
       ...
    end

Notice the `:before_start` option. We pass a block of code which is to be run,
just before the daemon is started. This block, along with starting the daemon,
is completely serialized. That is, if you're inside the block, then it's
guaranteed that no other process is running this block at the same time as well.

The `#query` method is the method for querying the search server with search
terms. It returns a list of result. It uses `DaemonController#connect`: one
passes a block of that method, which contains code for connecting to the
daemon. If the block returns nil, or if it raises `Errno::ECONNREFUSED`, then
`DaemonController#connect` will automatically take care of auto-starting the
Sphinx daemon for us.


A little bit of history
=======================

The issue of managing daemons has been a thorn in our eyes for quite some time
now. Until now, we've solved this problem by equipping any daemons that we
write with the ability to gracefully handle being concurrently started, the
ability to initialize as much as possible *before* forking into the background,
etc. However, equipping all this robustness into our code over and over is a
lot of work. We've considered documenting a standard behavior for daemons so
that they can properly support auto-starting and such.

However, we've recently realized that that's probably a futile effort.
Convincing everybody to write a lot of code for a bit more robustness is
probably not realistic. So we took the pragmatic approach and developed a
library which adds more robustness on top of daemons' existing behavior. And
thus, daemon_controller was born. It is a little bit less efficient compared to
when the daemon is designed from the beginning with such abilities in mind, but
it's compatible with virtually all daemons, and is easy to use.


Concurrency and compatibility notes
===================================
DaemonController uses a lock file and the Ruby `File#flock` API to guarantee
synchronization. This has a few implications:

 * On most Ruby implementations, including MRI, `File#flock` is implemented
   with the POSIX `flock()` system call or the Windows file locking APIs.
   This kind of file locking works pretty much the way we expect it would.
   Multiple threads can safely use daemon_controller concurrently. Multiple
   processes can safely use daemon_controller concurrently. There will be no
   race conditions.
   
   However `flock()` is not implemented on Solaris. daemon_controller, if
   used in MRI does not currently work on Solaris. You need to use JRuby
   which does not use `flock()` to implement `File#flock`.
   
 * On JRuby `File#flock` is implemented through the Java file locking API,
   which on Unix is implemented with the `fcntl()` system calls. This is a
   different kind of lock with very strange semantics.

   * If *any* process/thread closes the lock file, then the lock on that file
     will be removed even if that process/thread never requested a lock.
   * Fcntl locks are usually implemented indepedently from `flock()` locks so
     if a file is already locked with `flock()` then `fcntl()` will not block
     when.
   * The JVM's file locking API only allows inter-process synchronization. It
     cannot be used to synchronize threads. If a thread has obtained a file
     lock, then another thread within the same JVM process will not block upon
     trying to lock the same file.
   
   In other words, if you're on JRuby then don't concurrently access
   daemon_controller from multiple threads without manual locking. Also be
   careful with mixing MRI processes that use daemon_controller with JRuby
   processes that use daemon_controller.


API documentation
=================

Detailed API documentation is available in the form of inline comments in
`lib/daemon_controller.rb`.
