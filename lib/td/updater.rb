# -*- coding: utf-8 -*-
require "fileutils"
require "shellwords"
require "zip/zip"

module TreasureData
module Updater
  #
  # Toolbelt upgrade
  #

  def self.raise_error(message)
    # TODO: Replace better Exception class
    raise RuntimeError.new(message)
  end

  # copied from TreasureData::Helpers to avoid load issue.
  def self.home_directory
    on_windows? ? ENV['USERPROFILE'].gsub("\\","/") : ENV['HOME']
  end

  def self.on_windows?
    RUBY_PLATFORM =~ /mswin32|mingw32/
  end

  def self.on_mac?
    RUBY_PLATFORM =~ /-darwin\d/
  end

  def self.updating_lock_path
    File.join(home_directory, ".td", "updating")
  end

  def self.installed_client_path
    File.expand_path("../../../../../..", __FILE__)
  end

  def self.updated_client_path
    File.join(home_directory, ".td", "updated")
  end

  def self.latest_local_version
    installed_version = client_version_from_path(installed_client_path)
    updated_version = client_version_from_path(updated_client_path)
    if compare_versions(updated_version, installed_version) > 0
      updated_version
    else
      installed_version
    end
  end

  def self.get_client_version_file(path)
    td_gems = Dir[File.join(path, "vendor/gems/td-*")]
    td_gems.each { |td_gem|
      if td_gem =~ /#{"#{Regexp.escape(path)}\/vendor\/gems\/td-\\d*.\\d*.\\d*"}/
        return File.join(td_gem, "/lib/td/version.rb")
      end
    }
    nil
  end

  def self.client_version_from_path(path)
    if version_file = get_client_version_file(path)
      File.read(version_file).match(/TOOLBELT_VERSION = '([^']+)'/)[1]
    else
      '0.0.0'
    end
  end

  def self.disable(message)
    @disable = message
  end

  def self.disable?
    !@disable.nil?
  end

  def self.disable_message
    @disable
  end

  def self.wait_for_lock(path, wait_for = 5, check_every = 0.5)
    start = Time.now.to_i
    while File.exists?(path)
      sleep check_every
      if (Time.now.to_i - start) > wait_for
        raise_error "Unable to acquire update lock"
      end
    end
    begin
      FileUtils.touch(path)
      ret = yield
    ensure
      FileUtils.rm_f(path)
    end
    ret
  end

  def self.package_category
    case
    when on_windows?
      'exe'
    when on_mac?
      'pkg'
    else
      raise_error "Environment not supported"
    end
  end

  def self.fetch(url)
    require 'net/http'
    require 'openssl'

    http_class = Command.get_http_class

    # open-uri can't treat 'http -> https' redirection and
    # Net::HTTP.get_response can't get response from HTTPS endpoint.
    # So we use following code to avoid these issues.
    uri = URI(url)
    response =
      if uri.scheme == 'https' and ENV['HTTP_PROXY'].nil?
        # NOTE: SSL is force off for communications over proxy
        http = http_class.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.request(Net::HTTP::Get.new(uri.path))
      else
        http_class.get_response(uri)
      end

    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection then fetch(response['Location'])
    else
      raise Command::UpdateError,
            "An error occurred when fetching from '#{url}'."
      response.error!
    end
  end

  def self.endpoint_root
    ENV['TD_TOOLBELT_UPDATE_ROOT'] || "http://toolbelt.treasuredata.com"
  end

  def self.version_endpoint
    "#{endpoint_root}/version.#{package_category}"
  end

  def self.update_package_endpoint
    "#{endpoint_root}/td-update-#{package_category}.zip"
  end

  def self.update(autoupdate = false)
    wait_for_lock(updating_lock_path, 5) do
      require "td"
      require 'open-uri'
      require "tmpdir"
      require "zip/zip"

      latest_version = fetch(version_endpoint)

      if compare_versions(latest_version, latest_local_version) > 0
        Dir.mktmpdir do |download_dir|

          indicator = Command::TimeBasedDownloadProgressIndicator.new(
            "Downloading updated toolbelt package", Time.new.to_i, 2)
          # downloading the update compressed file
          File.open("#{download_dir}/td-update.zip", "wb") do |file|
            endpoint = update_package_endpoint
            puts "\npackage '#{endpoint}'... " unless ENV['TD_TOOLBELT_DEBUG'].nil?
            stream_fetch(endpoint, file) {
              indicator.update
            }
          end
          indicator.finish

          print "Unpacking updated toolbelt package..."
          Zip::ZipFile.open("#{download_dir}/td-update.zip") do |zip|
            zip.each do |entry|
              target = File.join(download_dir, entry.to_s)
              FileUtils.mkdir_p(File.dirname(target))
              zip.extract(entry, target) { true }
            end
          end
          print "done\n"

          FileUtils.rm "#{download_dir}/td-update.zip"

          old_version = latest_local_version
          new_version = client_version_from_path(download_dir)

          if compare_versions(new_version, old_version) < 0 && !autoupdate
            raise_error "Installed version (#{old_version}) is newer than the latest available update (#{new_version})"
          end

          FileUtils.rm_rf updated_client_path
          FileUtils.mkdir_p File.dirname(updated_client_path)
          FileUtils.cp_r(download_dir, updated_client_path)

          new_version
        end
      else
        false # already up to date
      end
    end
  ensure
    FileUtils.rm_f(updating_lock_path)
  end

  def self.compare_versions(first_version, second_version)
    first_version.split('.').map { |part| Integer(part) rescue part } <=> second_version.split('.').map { |part| Integer(part) rescue part }
  end

  def self.inject_libpath
    old_version = client_version_from_path(installed_client_path)
    new_version = client_version_from_path(updated_client_path)

    if compare_versions(new_version, old_version) > 0
      vendored_gems = Dir[File.join(updated_client_path, "vendor", "gems", "*")]
      vendored_gems.each do |vendored_gem|
        $:.unshift File.join(vendored_gem, "lib")
      end
      load('td/updater.rb') # reload updated updater
    end

    # check every hour if the toolbelt can be updated.
    # => If so, update in the background
    if File.exists?(last_toolbelt_autoupdate_timestamp)
      return if (Time.now.to_i - File.mtime(last_toolbelt_autoupdate_timestamp).to_i) < 60 * 60 * 1 # every 1 hours
    end
    log_path = File.join(home_directory, '.td', 'autoupdate.log')
    FileUtils.mkdir_p File.dirname(log_path)
    td_binary = File.expand_path($0)
    pid = if defined?(RUBY_VERSION) and RUBY_VERSION =~ /^1\.8\.\d+/
      fork do
        exec("#{Shellwords.escape(td_binary)} update &> #{Shellwords.escape(log_path)} 2>&1")
      end
    else
      log_file = File.open(log_path, "w")
      spawn(td_binary, 'update', :err => log_file, :out => log_file)
    end
    Process.detach(pid)
    FileUtils.mkdir_p File.dirname(last_toolbelt_autoupdate_timestamp)
    FileUtils.touch last_toolbelt_autoupdate_timestamp
  end

  def self.last_toolbelt_autoupdate_timestamp
    File.join(home_directory, ".td", "autoupdate.last")
  end

  #
  # td-import.jar upgrade
  #

  # locate the root of the td package which is 3 folders up from the location of this file
  def self.jarfile_dest_path
    File.join(home_directory, ".td", "java")
  end

  private
  def self.stream_fetch(url, binfile, &progress)
    require 'net/http'

    uri = URI(url)
    http_class = Command.get_http_class
    http = http_class.new(uri.host, uri.port)

    # NOTE: keep SSL off when using a proxy
    if uri.scheme == 'https' and ENV['HTTP_PROXY'].nil?
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    http.request_get(uri.path) {|response|
      if response.class == Net::HTTPOK
        # print a . every tick_period seconds
        response.read_body do |chunk|
          binfile.write chunk
          progress.call unless progress.nil?
        end
        return true
      elsif response.class == Net::HTTPFound || \
            response.class == Net::HTTPRedirection
        unless ENV['TD_TOOLBELT_DEBUG'].nil?
          puts "redirect '#{url}' to '#{response['Location']}'... "
        end
        return stream_fetch(response['Location'], binfile, &progress)
      else
        raise Command::UpdateError,
              "An error occurred when fetching from '#{uri}' " +
              "(#{response.class.to_s}: #{response.message})."
        return false
      end
    }
  end

  private
  def jar_update(hourly = false)
    require 'rexml/document'
    require 'open-uri'
    require 'fileutils'

    maven_repo = "http://central.maven.org/maven2/com/treasuredata/td-import"

    begin
      xml = Updater.fetch("#{maven_repo}/maven-metadata.xml")
    rescue Exception => exc
      raise Command::UpdateError,
            "There was a problem accessing the remote XML resource " +
            "'#{maven_repo}/maven-metadata.xml' (#{exc.class.to_s}: #{exc.message})"
    end
    if xml.nil? || xml.empty?
      raise Command::UpdateError,
            "The remote XML resource '#{maven_repo}/maven-metadata.xml' " +
            "returned an empty file."
    end

    # read version and update date from the xml file
    doc = REXML::Document.new(xml)
    updated = Time.strptime(REXML::XPath.match(doc,
      '/metadata/versioning/lastUpdated').first.text, "%Y%m%d%H%M%S")
    version = REXML::XPath.match(doc, '/metadata/versioning/release').first.text

    # Convert into UTF to compare time correctly
    updated = (updated + updated.gmt_offset).utc unless updated.gmt?
    last_updated = existent_jar_updated_time

    if updated > last_updated
      FileUtils.mkdir_p(jarfile_dest_path) unless File.exists?(Updater.jarfile_dest_path)
      Dir.chdir Updater.jarfile_dest_path

      File.open('VERSION', 'w') {|f|
        if hourly
          f.print "#{version} via hourly jar auto-update"
        else
          f.print "#{version} via import:jar_update command"
        end
      }
      File.open('td-import-java.version', 'w') {|f|
        f.print "#{version} #{updated}"
      }

      status = nil
      indicator = Command::TimeBasedDownloadProgressIndicator.new(
        "Updating td-import.jar", Time.new.to_i, 2)
      File.open('td-import.jar.new', 'wb') {|binfile|
        status = Updater.stream_fetch("#{maven_repo}/#{version}/td-import-#{version}-jar-with-dependencies.jar", binfile) {
          indicator.update
        }
      }
      indicator.finish()

      if status
        puts "Installed td-import.jar v#{version} in '#{Updater.jarfile_dest_path}'.\n"
        File.rename 'td-import.jar.new', 'td-import.jar'
      else
        puts "Update of td-import.jar failed." unless ENV['TD_TOOLBELT_DEBUG'].nil?
        File.delete 'td-import.jar.new' if File.exists? 'td-import.jar.new'
      end
    else
      puts 'Installed td-import.jar is already at the latest version.' unless hourly
    end
  end

  def check_n_update_jar(hourly = false)
    if hourly
      if !ENV['TD_TOOLBELT_JAR_UPDATE'].nil?
        # also validates the TD_TOOLBELT_JAR_UPDATE environment variable value
        if ENV['TD_TOOLBELT_JAR_UPDATE'] == "0"
          puts "Warning: Bulk Import JAR auto-update disabled by TD_TOOLBELT_JAR_UPDATE=0"
          return
        elsif ENV['TD_TOOLBELT_JAR_UPDATE'] != "1"
          raise UpdateError,
                "Invalid value for TD_TOOLBELT_JAR_UPDATE environment variable. Only 0 and 1 are allowed."
        end
      end

      if File.exists?(last_jar_autoupdate_timestamp) && \
       (Time.now - File.mtime(last_jar_autoupdate_timestamp)).to_i < (60 * 60 * 1) # every hour
        return
      end
    end
    jar_update(hourly)
    FileUtils.touch last_jar_autoupdate_timestamp
  end

  private
  def last_jar_autoupdate_timestamp
    File.join(Updater.jarfile_dest_path, "td-import-java.version")
  end

  private
  def existent_jar_updated_time
    files = Command.find_files("td-import-java.version", [Updater.jarfile_dest_path])
    if files.empty?
      return Time.at(0)
    end
    content = File.read(files.first)
    index = content.index(' ')
    time = nil
    if index.nil?
      time = Time.at(0).utc
    else
      time = Time.parse(content[index+1..-1].strip).utc
    end
    time
  end

end # module Updater
end # module TreasureData