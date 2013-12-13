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
DEBIAN_PACKAGE_REVISION = 1
ALL_DISTRIBUTIONS  = string_option('DEBIAN_DISTROS', 'saucy precise lucid').split(/[ ,]/)
ORIG_TARBALL_FILES = lambda do
	require 'daemon_controller/packaging'
	Dir[*DAEMON_CONTROLLER_FILES] - Dir[*DAEMON_CONTROLLER_DEBIAN_EXCLUDE_FILES]
end

# Implements a simple preprocessor language which combines elements in the C
# preprocessor with ERB:
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
#     Today is <%= Time.now %>.
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
#     Today is 2013-08-11 22:37:06 +0200.
# 
# Highlights:
# 
#  * #if blocks can be nested.
#  * Expressions are Ruby expressions, evaluated within the binding of a
#    Preprocessor::Evaluator object.
#  * Text inside #if/#elif/#else are automatically unindented.
#  * ERB compatible.
class Preprocessor
	def initialize
		require 'erb' if !defined?(ERB)
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
		@filename    = filename
		@lineno      = 1
		@indentation = 0

		each_line(filename, the_binding) do |line|
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
			when "DEBHELPER"
				output.puts(line)
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
		"saucy"    => "13.10",
		"trusty"   => "14.04"
	}
	DEBIAN_DISTRIBUTIONS = {
		"squeeze"  => "20110206",
		"wheezy"   => "20130504"
	}
	REDHAT_ENTERPRISE_DISTRIBUTIONS = {
		"el6"      => "el6.0"
	}
	AMAZON_DISTRIBUTIONS = {
		"amazon"   => "amazon"
	}

	# Provides the DSL that's accessible within.
	class Evaluator
		def _infer_distro_table(name)
			if UBUNTU_DISTRIBUTIONS.has_key?(name)
				return UBUNTU_DISTRIBUTIONS
			elsif DEBIAN_DISTRIBUTIONS.has_key?(name)
				return DEBIAN_DISTRIBUTIONS
			elsif REDHAT_ENTERPRISE_DISTRIBUTIONS.has_key?(name)
				return REDHAT_ENTERPRISE_DISTRIBUTIONS
			elsif AMAZON_DISTRIBUTIONS.has_key?(name)
				return AMAZON_DISTRIBUTIONS
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
				return false if table1 != table2
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

	def each_line(filename, the_binding)
		data = File.open(filename, 'r') do |f|
			erb = ERB.new(f.read, nil, "-")
			erb.filename = filename
			erb.result(the_binding)
		end
		data.each_line do |line|
			yield line.chomp
		end
	end
	
	def recognize_command(line)
		if line =~ /^([\s\t]*)#(.+)/
			indentation_str = $1
			command = $2

			# Declare tabs as equivalent to 4 spaces. This is necessary for
			# Makefiles in which the use of tabs is required.
			indentation_str.gsub!("\t", "    ")

			name = command.scan(/^\w+/).first
			# Ignore shebangs and comments.
			return if name.nil?

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
		# Declare tabs as equivalent to 4 spaces. This is necessary for
		# Makefiles in which the use of tabs is required.
		found = $1.to_s.gsub("\t", "    ").size
		
		if found >= @indentation
			# Tab-friendly way to remove indentation.
			remaining = @indentation
			line = line.dup
			while remaining > 0
				if line[0..0] == " "
					remaining -= 1
				else
					# This is a tab.
					remaining -= 4
				end
				line.slice!(0, 1)
			end
			return line
		else
			terminate "wrong indentation: found #{found} characters, should be at least #{@indentation}"
		end
	end

	def debug(message)
		puts "DEBUG:#{@lineno}: #{message}" if @debug
	end

	def terminate(message)
		abort "*** ERROR: #{@filename} line #{@lineno}: #{message}"
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
		"#{DEBIAN_NAME} (#{PACKAGE_VERSION}-#{DEBIAN_PACKAGE_REVISION}~#{distribution}1) #{distribution}; urgency=low\n" +
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
		sh "cd #{PKG_DIR} && find #{DEBIAN_NAME}_#{PACKAGE_VERSION} -print0 | xargs -0 touch -d '2013-10-27 00:00:00 UTC'"
		sh "cd #{PKG_DIR} && tar -c #{DEBIAN_NAME}_#{PACKAGE_VERSION} | gzip --no-name --best > #{DEBIAN_NAME}_#{PACKAGE_VERSION}.orig.tar.gz"
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

desc "Build Debian source packages"
task 'debian:source_packages' => 'debian:orig_tarball' do
	ALL_DISTRIBUTIONS.each do |distribution|
		create_debian_package_dir(distribution)
	end
	ALL_DISTRIBUTIONS.each do |distribution|
		sh "cd #{PKG_DIR}/#{distribution} && debuild -S -us -uc"
	end
end

desc "Build Debian source packages to be uploaded to Launchpad"
task 'debian:launchpad' => 'debian:orig_tarball' do
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


##### RPM packaging support #####

RPM_NAME = "rubygem-daemon_controller"
RPMBUILD_ROOT = File.expand_path("~/rpmbuild")
MOCK_OFFLINE = boolean_option('MOCK_OFFLINE', false)
ALL_RPM_DISTROS = {
	"el6" => { :mock_chroot_name => "epel-6", :distro_name => "Enterprise Linux 6" },
	"amazon" => { :mock_chroot_name => "epel-6", :distro_name => "Amazon Linux" }
}

desc "Build gem for use in RPM building"
task 'rpm:gem' do
	rpm_source_dir = "#{RPMBUILD_ROOT}/SOURCES"
	sh "gem build #{PACKAGE_NAME}.gemspec"
	sh "cp #{PACKAGE_NAME}-#{PACKAGE_VERSION}.gem #{rpm_source_dir}/"
end

desc "Build RPM for local machine"
task 'rpm:local' => 'rpm:gem' do
	distro_id = `./rpm/get_distro_id.py`.strip
	rpm_spec_dir = "#{RPMBUILD_ROOT}/SPECS"
	spec_target_dir = "#{rpm_spec_dir}/#{distro_id}"
	spec_target_file = "#{spec_target_dir}/#{RPM_NAME}.spec"

	sh "mkdir -p #{spec_target_dir}"
	puts "Generating #{spec_target_file}"
	Preprocessor.new.start("rpm/#{RPM_NAME}.spec.template",
		spec_target_file,
		:distribution => distro_id)

	sh "rpmbuild -ba #{spec_target_file}"
end

def create_rpm_build_task(distro_id, mock_chroot_name, distro_name)
	desc "Build RPM for #{distro_name}"
	task "rpm:#{distro_id}" => 'rpm:gem' do
		rpm_spec_dir = "#{RPMBUILD_ROOT}/SPECS"
		spec_target_dir = "#{rpm_spec_dir}/#{distro_id}"
		spec_target_file = "#{spec_target_dir}/#{RPM_NAME}.spec"
		maybe_offline = MOCK_OFFLINE ? "--offline" : nil

		sh "mkdir -p #{spec_target_dir}"
		puts "Generating #{spec_target_file}"
		Preprocessor.new.start("rpm/#{RPM_NAME}.spec.template",
			spec_target_file,
			:distribution => distro_id)

		sh "rpmbuild -bs #{spec_target_file}"
		sh "mock --verbose #{maybe_offline} " +
			"-r #{mock_chroot_name}-x86_64 " +
			"--resultdir '#{PKG_DIR}/#{distro_id}' " +
			"rebuild #{RPMBUILD_ROOT}/SRPMS/#{RPM_NAME}-#{PACKAGE_VERSION}-1#{distro_id}.src.rpm"
	end
end

ALL_RPM_DISTROS.each_pair do |distro_id, info|
	create_rpm_build_task(distro_id, info[:mock_chroot_name], info[:distro_name])
end

desc "Build RPMs for all distributions"
task "rpm:all" => ALL_RPM_DISTROS.keys.map { |x| "rpm:#{x}" }

desc "Publish RPMs for all distributions"
task "rpm:publish" do
	server = "juvia-helper.phusion.nl"
	remote_dir = "/srv/oss_binaries_passenger/yumgems/phusion-misc"
	rsync = "rsync -z -r --delete --progress"

	ALL_RPM_DISTROS.each_key do |distro_id|
		if !File.exist?("#{PKG_DIR}/#{distro_id}")
			abort "No packages built for #{distro_id}. Please run 'rake rpm:all' first."
		end
	end
	ALL_RPM_DISTROS.each_key do |distro_id|
		sh "rpm --resign --define '%_signature gpg' --define '%_gpg_name #{PACKAGE_SIGNING_KEY}' #{PKG_DIR}/#{distro_id}/*.rpm"
	end
	sh "#{rsync} #{server}:#{remote_dir}/latest/ #{PKG_DIR}/yumgems/"
	ALL_RPM_DISTROS.each_key do |distro_id|
		distro_dir = "#{PKG_DIR}/#{distro_id}"
		repo_dir = "#{PKG_DIR}/yumgems/#{distro_id}"
		sh "mkdir -p #{repo_dir}"
		sh "cp #{distro_dir}/#{RPM_NAME}*.rpm #{repo_dir}/"
		sh "createrepo #{repo_dir}"
	end
	sh "ssh #{server} 'rm -rf #{remote_dir}/new && cp -dpR #{remote_dir}/latest #{remote_dir}/new'"
	sh "#{rsync} #{PKG_DIR}/yumgems/ #{server}:#{remote_dir}/new/"
	sh "ssh #{server} 'rm -rf #{remote_dir}/previous && mv #{remote_dir}/latest #{remote_dir}/previous && mv #{remote_dir}/new #{remote_dir}/latest'"
end
