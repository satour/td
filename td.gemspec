# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{td}
  s.version = "0.9.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sadayuki Furuhashi"]
  s.date = %q{2011-09-20}
  s.default_executable = %q{td}
  s.executables = ["td"]
  s.extra_rdoc_files = [
    "ChangeLog",
     "README.rdoc"
  ]
  s.files = [
    "lib/td.rb",
     "lib/td/command/account.rb",
     "lib/td/command/apikey.rb",
     "lib/td/command/common.rb",
     "lib/td/command/db.rb",
     "lib/td/command/help.rb",
     "lib/td/command/import.rb",
     "lib/td/command/job.rb",
     "lib/td/command/list.rb",
     "lib/td/command/query.rb",
     "lib/td/command/runner.rb",
     "lib/td/command/sched.rb",
     "lib/td/command/schema.rb",
     "lib/td/command/server.rb",
     "lib/td/command/table.rb",
     "lib/td/config.rb",
     "lib/td/version.rb"
  ]
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Treasure Data command line tool}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<msgpack>, ["~> 0.4.4"])
      s.add_runtime_dependency(%q<json>, [">= 1.4.3"])
      s.add_runtime_dependency(%q<hirb>, [">= 0.4.5"])
      s.add_runtime_dependency(%q<td-client>, ["~> 0.8.2"])
      s.add_runtime_dependency(%q<td-logger>, ["~> 0.2.4"])
    else
      s.add_dependency(%q<msgpack>, ["~> 0.4.4"])
      s.add_dependency(%q<json>, [">= 1.4.3"])
      s.add_dependency(%q<hirb>, [">= 0.4.5"])
      s.add_dependency(%q<td-client>, ["~> 0.8.2"])
      s.add_dependency(%q<td-logger>, ["~> 0.2.4"])
    end
  else
    s.add_dependency(%q<msgpack>, ["~> 0.4.4"])
    s.add_dependency(%q<json>, [">= 1.4.3"])
    s.add_dependency(%q<hirb>, [">= 0.4.5"])
    s.add_dependency(%q<td-client>, ["~> 0.8.2"])
    s.add_dependency(%q<td-logger>, ["~> 0.2.4"])
  end
end

