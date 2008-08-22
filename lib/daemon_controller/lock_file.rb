class DaemonController
class LockFile
	def initialize(filename)
		@filename = filename
	end
	
	def exclusive_lock
		File.open(@filename, 'w') do |f|
			if Fcntl.const_defined? :F_SETFD
				f.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
			end
			f.flock(File::LOCK_EX)
			yield
		end
	end
	
	def shared_lock
		File.open(@filename, 'w') do |f|
			if Fcntl.const_defined? :F_SETFD
				f.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
			end
			f.flock(File::LOCK_SH)
			yield
		end
	end
end # class PidFile
end # class DaemonController
