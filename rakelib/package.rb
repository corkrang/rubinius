
def write_md5_digest_file(filename)
  require 'digest/md5'
  digest = Digest::MD5.new

  File.open(filename, "rb") do |f|
    until f.eof?
      digest << f.read(1024)
    end
  end

  digest_file = "#{filename}.md5"
  File.open(digest_file, "w") do |f|
    f.puts digest.hexdigest
  end

  puts "Computed MD5 to #{digest_file}"
end

def write_sha1_digest_file(filename)
  require 'digest/sha1'
  digest = Digest::SHA1.new

  File.open(filename, "rb") do |f|
    until f.eof?
      digest << f.read(1024)
    end
  end

  digest_file = "#{filename}.sha1"
  File.open(digest_file, "w") do |f|
    f.puts digest.hexdigest
  end

  puts "Computed SHA1 to #{digest_file}"
end

class RubiniusPackager
  attr_writer :ruby_version, :release, :prefix, :root, :bin, :config, :archive, :package

  def initialize(options={})
    @ruby_version = options[:ruby_version]
    @release = options[:release]
    @release_date = options[:release_date]
    @prefix = options[:prefix]
    @root = options[:root]
    @bin = options[:bin]
    @config = options[:config]
    @archive = options[:archive]
    @package = options[:package]
  end

  # eg "18", "1.8", "18,19", "1.8,1.9"
  def ruby_version
    (@ruby_version || "18").gsub(/\s|\./, "")
  end

  def single_version?
    not ruby_version.index(",")
  end

  def rbx_version
    BUILD_CONFIG[:version].match(/^(\d+\.\d+\.\d+)/)[0]
  end

  # "nightly", "weekly", "rcN". no value indicates standard release
  def release
    @release
  end

  def release_date
    @release_date || DateTime.now.strftime("%F")
  end

  # passed verbatim to --prefix
  def prefix
    default = "/usr/local/rubinius/#{rbx_version}"
    default += ".#{release}" if release
    default += "-#{ruby_version}" if single_version?
    @prefix || default
  end

  # root directory of the build
  def root
    if BUILD_CONFIG[:stagingdir]
      default = BUILD_CONFIG[:stagingdir][0...-BUILD_CONFIG[:prefixdir].size]
    else
      default = BUILD_CONFIG[:sourcedir]
    end
    @root || default
  end

  # path for a binary symlink
  def bin
    @bin
  end

  # any configure options
  def config
    default = ["--prefix=#{prefix} --preserve-prefix"]
    default << ["--enable-version=#{ruby_version}"] if single_version?
    default << ["--release=#{release} --release-date=#{release_date}"] if release
    @config || default.join(" ")
  end

  # "zip", "tar.gz", "tar.bz2"
  def archive
    @archive || "tar.gz"
  end

  # name of the final package file minus #archive
  def package
    default = "rubinius-#{rbx_version}"
    if release[0, 2] == "rc"
      default += "-#{release}"
    else
      default += "-#{release}#{date_stamp}"
    end
    default += "-d#{ruby_version}" if single_version?
    @package || default
  end

  def date_stamp
    Time.now.strftime("%Y%m%d")
  end

  def create_archive(package_name)
    case archive
    when "zip"
      sh "zip --symlinks -r #{package_name} *"
    when "tar.gz"
      sh "tar -c -f - * | gzip > #{package_name}"
    when "tar.bz2"
      sh "tar -c -f - * | bzip2 -9 > #{package_name}"
    else
      raise RuntimeError, "unknown archive format: #{archive}"
    end

    sh "mv #{root}/#{package_name} #{BUILD_CONFIG[:sourcedir]}"
  end

  def build
    sh "rm -rf #{BUILD_CONFIG[:sourcedir]}/staging"

    package_name = package + "." + archive
    sh "rm -rf #{package_name}*"

    ENV["RELEASE"] = "1"
    sh "./configure #{config}"
    load_configuration

    sh "rake -q clean; rake -q build"

    if bin
      sh "mkdir -p #{root}#{File.dirname(bin)}"

      bin = "#{prefix}#{BUILD_CONFIG[:bindir]}"
      bin_link = "#{root}#{bin}"

      sh "ln -sf #{bin} #{bin_link}"
    end

    Dir.chdir(root) { create_archive package_name }

    write_md5_digest_file package_name
    write_sha1_digest_file package_name
  rescue Object => e
    # Some rake versions swallow the backtrace, so we do it explicitly.
    STDERR.puts e.message, e.backtrace
  end
end
