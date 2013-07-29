$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require 'daemon_controller/version'

PACKAGE_NAME    = "daemon_controller"
PACKAGE_VERSION = DaemonController::VERSION_STRING
PACKAGE_SIGNING_KEY = "0x0A212A8C"
MAINTAINER_NAME  = "Hongli Lai"
MAINTAINER_EMAIL = "hongli@phusion.nl"

desc "Run the unit tests"
task :test do
	sh "rspec -f s -c spec/*_spec.rb"
end

desc "Build, sign & upload gem"
task 'package:release' do
	sh "git tag -s release-#{PACKAGE_VERSION}"
	sh "gem build #{PACKAGE_NAME}.gemspec --sign --key #{PACKAGE_SIGNING_KEY}"
	puts "Proceed with pushing tag to Github and uploading the gem? [y/n]"
	if STDIN.readline == "y\n"
		sh "git push origin release-#{PACKAGE_VERSION}"
		sh "gem push #{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem"
	else
		puts "Did not upload the gem."
	end
end


##### Utilities #####

def string_option(name, default_value = nil)
	value = ENV[name]
	if value.nil? || value.empty?
		return default_value
	else
		return value
	end
end

def boolean_option(name, default_value = false)
	value = ENV[name]
	if value.nil? || value.empty?
		return default_value
	else
		return value == "yes" || value == "on" || value == "true" || value == "1"
	end
end


##### Debian packaging support #####

PKG_DIR         = string_option('PKG_DIR', "pkg")
DEBIAN_NAME     = "ruby-daemon-controller"
ALL_DISTRIBUTIONS  = ["raring", "precise", "lucid"]
ORIG_TARBALL_FILES = lambda do
	require 'daemon_controller/packaging'
	Dir[*DAEMON_CONTROLLER_FILES] - Dir[*DAEMON_CONTROLLER_DEBIAN_EXCLUDE_FILES]
end

# Implements a simple preprocessor language:
# 
#     Today
#     #if @today == :fine
#         is a fine day.
#     #elif @today == :good
#         is a good day.
#     #else
#         is a sad day.
#     #endif
#     Let's go walking.
# 
# When run with...
# 
#     Preprocessor.new.start('input.txt', 'output.txt', :today => :fine)
# 
# ...will produce:
# 
#     Today
#     is a fine day.
#     Let's go walking.
# 
# Highlights:
# 
#  * #if blocks can be nested.
#  * Expressions are Ruby expressions, evaluated within the binding of a
#    Preprocessor::Evaluator object.
#  * Text inside #if/#elif/#else are automatically unindented.
class Preprocessor
	def initialize
		@indentation_size = 4
		@debug = boolean_option('DEBUG')
	end

	def start(filename, output_filename, variables = {})
		if output_filename
			temp_output_filename = "#{output_filename}._new"
			output = File.open(temp_output_filename, 'w')
		else
			output = STDOUT
		end
		the_binding  = create_binding(variables)
		context      = []
		@lineno      = 1
		@indentation = 0

		each_line(filename) do |line|
			debug("context=#{context.inspect}, line=#{line.inspect}")

			name, args_string, cmd_indentation = recognize_command(line)
			case name
			when "if"
				case context.last
				when nil, :if_true, :else_true
					check_indentation(cmd_indentation)
					result = the_binding.eval(args_string, filename, @lineno)
					context.push(result ? :if_true : :if_false)
					inc_indentation
				when :if_false, :else_false, :if_ignore
					check_indentation(cmd_indentation)
					inc_indentation
					context.push(:if_ignore)
				else
					terminate "#if is not allowed in this context"
				end
			when "elif"
				case context.last
				when :if_true
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
					context[-1] = :if_false
				when :if_false
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
					result = the_binding.eval(args_string, filename, @lineno)
					context[-1] = result ? :if_true : :if_false
				when :else_true, :else_false
					terminate "#elif is not allowed after #else"
				when :if_ignore
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
				else
					terminate "#elif is not allowed outside #if block"
				end
			when "else"
				case context.last
				when :if_true
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
					context[-1] = :else_false
				when :if_false
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
					context[-1] = :else_true
				when :else_true, :else_false
					terminate "it is not allowed to have multiple #else clauses in one #if block"
				when :if_ignore
					dec_indentation
					check_indentation(cmd_indentation)
					inc_indentation
				else
					terminate "#else is not allowed outside #if block"
				end
			when "endif"
				case context.last
				when :if_true, :if_false, :else_true, :else_false, :if_ignore
					dec_indentation
					check_indentation(cmd_indentation)
					context.pop
				else
					terminate "#endif is not allowed outside #if block"
				end
			when "", nil
				# Either a comment or not a preprocessor command.
				case context.last
				when nil, :if_true, :else_true
					output.puts(unindent(line))
				else
					# Check indentation but do not output.
					unindent(line)
				end
			else
				terminate "Unrecognized preprocessor command ##{name.inspect}"
			end

			@lineno += 1
		end
	ensure
		if output_filename && output
			output.close
			stat = File.stat(filename)
			File.chmod(stat.mode, temp_output_filename)
			File.chown(stat.uid, stat.gid, temp_output_filename) rescue nil
			File.rename(temp_output_filename, output_filename)
		end
	end

private
	UBUNTU_DISTRIBUTIONS = {
		"lucid"    => "10.04",
		"maverick" => "10.10",
		"natty"    => "11.04",
		"oneiric"  => "11.10",
		"precise"  => "12.04",
		"quantal"  => "12.10",
		"raring"   => "13.04",
		"saucy"    => "13.10"
	}

	# Provides the DSL that's accessible within.
	class Evaluator
		def _infer_distro_table(name)
			if UBUNTU_DISTRIBUTIONS.has_key?(name)
				return UBUNTU_DISTRIBUTIONS
			end
		end

		def is_distribution?(expr)
			if @distribution.nil?
				raise "The :distribution variable must be set"
			else
				if expr =~ /^(>=|>|<=|<|==|\!=)[\s]*(.+)/
					comparator = $1
					name = $2
				else
					raise "Invalid expression #{expr.inspect}"
				end

				table1 = _infer_distro_table(@distribution)
				table2 = _infer_distro_table(name)
				raise "Distribution name #{@distribution.inspect} not recognized" if !table1
				raise "Distribution name #{name.inspect} not recognized" if !table2
				v1 = table1[@distribution]
				v2 = table2[name]
				
				case comparator
				when ">"
					return v1 > v2
				when ">="
					return v1 >= v2
				when "<"
					return v1 < v2
				when "<="
					return v1 <= v2
				when "=="
					return v1 == v2
				when "!="
					return v1 != v2
				else
					raise "BUG"
				end
			end
		end
	end

	def each_line(filename)
		File.open(filename, 'r') do |f|
			while true
				begin
					line = f.readline.chomp
				rescue EOFError
					break
				end
				yield line
			end
		end
	end
	
	def recognize_command(line)
		if line =~ /^([\s\t]*)#(.+)/
			indentation_str = $1
			command = $2
			name = command.scan(/^\w+/).first
			args_string = command.sub(/^#{Regexp.escape(name)}[\s\t]*/, '')
			return [name, args_string, indentation_str.to_s.size]
		else
			return nil
		end
	end

	def create_binding(variables)
		object = Evaluator.new
		variables.each_pair do |key, val|
			object.send(:instance_variable_set, "@#{key}", val)
		end
		return object.instance_eval do
			binding
		end
	end

	def inc_indentation
		@indentation += @indentation_size
	end

	def dec_indentation
		@indentation -= @indentation_size
	end

	def check_indentation(expected)
		if expected != @indentation
			terminate "wrong indentation: found #{expected} characters, should be #{@indentation}"
		end
	end

	def unindent(line)
		line =~ /^([\s\t]*)/
		found = $1.to_s.size
		if found >= @indentation
			return line[@indentation .. -1]
		else
			terminate "wrong indentation: found #{found} characters, should be at least #{@indentation}"
		end
	end

	def debug(message)
		puts "DEBUG:#{@lineno}: #{message}" if @debug
	end

	def terminate(message)
		abort "*** ERROR: line #{@lineno}: #{message}"
	end
end

def recursive_copy_files(files, destination_dir, preprocess = false, variables = {})
	require 'fileutils' if !defined?(FileUtils)
	files.each_with_index do |filename, i|
		dir = File.dirname(filename)
		if !File.exist?("#{destination_dir}/#{dir}")
			FileUtils.mkdir_p("#{destination_dir}/#{dir}")
		end
		if !File.directory?(filename)
			if preprocess && filename =~ /\.template$/
				real_filename = filename.sub(/\.template$/, '')
				FileUtils.install(filename, "#{destination_dir}/#{real_filename}")
				Preprocessor.new.start(filename, "#{destination_dir}/#{real_filename}",
					variables)
			else
				FileUtils.install(filename, "#{destination_dir}/#{filename}")
			end
		end
		printf "\r[%5d/%5d] [%3.0f%%] Copying files...", i + 1, files.size, i * 100.0 / files.size
		STDOUT.flush
	end
	printf "\r[%5d/%5d] [%3.0f%%] Copying files...\n", files.size, files.size, 100
end

def create_debian_package_dir(distribution)
	require 'time'

	variables = {
		:distribution => distribution
	}

	root = "#{PKG_DIR}/#{distribution}"
	sh "rm -rf #{root}"
	sh "mkdir -p #{root}"
	recursive_copy_files(ORIG_TARBALL_FILES.call, root)
	recursive_copy_files(Dir["debian.template/**/*"], root,
		true, variables)
	sh "mv #{root}/debian.template #{root}/debian"
	changelog = File.read("#{root}/debian/changelog")
	changelog =
		"#{DEBIAN_NAME} (#{PACKAGE_VERSION}-1~#{distribution}1) #{distribution}; urgency=low\n" +
		"\n" +
		"  * Package built.\n" +
		"\n" +
		" -- #{MAINTAINER_NAME} <#{MAINTAINER_EMAIL}>  #{Time.now.rfc2822}\n\n" +
		changelog
	File.open("#{root}/debian/changelog", "w") do |f|
		f.write(changelog)
	end
end

task 'debian:orig_tarball' do
	if File.exist?("#{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz")
		puts "Debian orig tarball #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz already exists."
	else
		sh "rm -rf #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}"
		sh "mkdir -p #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}"
		recursive_copy_files(ORIG_TARBALL_FILES.call, "#{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}")
		sh "cd #{PKG_DIR} && tar -c #{DEBIAN_NAME}_#{PACKAGE_VERSION} | gzip --best > #{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz"
	end
end

desc "Build Debian source and binary package(s) for local testing"
task 'debian:dev' do
	sh "rm -f #{PKG_DIR}/#{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz"
	Rake::Task["debian:clean"].invoke
	Rake::Task["debian:orig_tarball"].invoke
	case distro = string_option('DISTRO', 'current')
	when 'current'
		distributions = [File.read("/etc/lsb-release").scan(/^DISTRIB_CODENAME=(.+)/).first.first]
	when 'all'
		distributions = ALL_DISTRIBUTIONS
	else
		distributions = distro.split(',')
	end
	distributions.each do |distribution|
		create_debian_package_dir(distribution)
		sh "cd #{PKG_DIR}/#{distribution} && dpkg-checkbuilddeps"
	end
	distributions.each do |distribution|
		sh "cd #{PKG_DIR}/#{distribution} && debuild -F -us -uc"
	end
end

desc "Build Debian source packages to be uploaded to repositories"
task 'debian:production' => 'debian:orig_tarball' do
	ALL_DISTRIBUTIONS.each do |distribution|
		create_debian_package_dir(distribution)
		sh "cd #{PKG_DIR}/#{distribution} && dpkg-checkbuilddeps"
	end
	ALL_DISTRIBUTIONS.each do |distribution|
		sh "cd #{PKG_DIR}/#{distribution} && debuild -S -sa -k#{PACKAGE_SIGNING_KEY}"
	end
end

desc "Clean Debian packaging products, except for orig tarball"
task 'debian:clean' do
	files = Dir["#{PKG_DIR}/*.{changes,build,deb,dsc,upload}"]
	sh "rm -f #{files.join(' ')}"
	sh "rm -rf #{PKG_DIR}/dev"
	ALL_DISTRIBUTIONS.each do |distribution|
		sh "rm -rf #{PKG_DIR}/#{distribution}"
	end
	sh "rm -rf #{PKG_DIR}/*.debian.tar.gz"
end
