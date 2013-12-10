TEMPLATE_HOST = ENV.fetch('TEMPLATE_HOST', 'https://raw.github.com/thegarage/thegarage-template')
TEMPLATE_BRANCH = ENV.fetch('TEMPLATE_BRANCH', 'master')

# helper method to wrap a chunk of code
# with consistent output + a git commit message
def step(message)
  header = '#' * 80
  puts "\n\n"
  puts header
  puts message + '...'
  puts header
  yield
end

# shortcut method to delete existing file
# and replace with new contents
def replace_file(filename, data)
  remove_file filename
  create_file filename, data
end

# helper method to run a command and ensure success
# by default the thor run command does *not* exit
# the process when the command fails
def run_command(command, options = {})
  status = run(command, options)
  fail "#{command} failed" unless status
end

# shortcut method to add a gem to the
# gemfile/.lock/cache, and install it
def install_gem(gem_name, options = {})
  if options[:group]
    gem gem_name, group: options[:group]
  else
    gem gem_name
  end
  run_command "gem install #{gem_name}"
  run_command 'bundle install --local'
end

# download remote file from remote repo and save to local path
def get_file(path)
  get File.join(TEMPLATE_HOST, TEMPLATE_BRANCH, path), path
end

# Asking for sensitive information to be used later.
newrelic_key = ask("What is your NewRelic license key(enter nothing if you don't have one)?")

honeybadger_api_key = ask("What is your Honeybadger API key(enter nothing if you don't have one)?")

travis_campfire_config = if yes?("Do you want TravisCI Campfire Notifications?")
  travis_campfire_subdomain = ask("What's your Campfire subdomain?")
  travis_campfire_api_key = ask("What is your API key?")
  travis_campfire_room_id = ask("What is your Campfire room ID(not the name)?")
  <<-EOS.strip_heredoc
    notifications:
      campfire: #{travis_campfire_subdomain}:#{travis_campfire_api_key}@#{travis_campfire_room_id}
      on_success: change
      on_failure: always
  EOS
else
  nil
end

gitignore = <<-EOS
# See http://help.github.com/ignore-files/ for more about ignoring files.
#
# If you find yourself ignoring temporary files generated by your text editor
# or operating system, you probably want to add a global ignore instead:
#   git config --global core.excludesfile '~/.gitignore_global'

# Ignore bundler config.
/.bundle

# Ignore all logfiles and tempfiles.
/log/*.log
/tmp

# OSX files
.DS_Store

EOS

env = <<-EOS
# options for building urls
DEFAULT_URL_PROTOCOL=http
DEFAULT_URL_HOST=localhost:3000

EOS

step 'Setup initial project Gemfile' do
  replace_file 'Gemfile', ''
  add_source "https://rubygems.org"
  insert_into_file 'Gemfile', "ruby '2.0.0'", after: "source .*\n"

  gem 'rails', '~> 4.0.1'
  gem 'jquery-rails'
  gem 'sass-rails', '~> 4.0.0'
  gem 'uglifier', '>= 1.3.0'
  gem 'haml', '~> 4.0.3'
  gem 'rails-console-tweaks'
  gem 'pg'
  gem 'pry-rails'
  gem 'dotenv-rails'
  gem 'thegarage-gitx', group: [:development, :test]
  run_command 'bundle package'

  create_file '.env', env
  create_file '.ruby-version', '2.0.0-p247'
  replace_file '.gitignore', gitignore
end

step 'Setup Rakefile default_tasks' do
  append_to_file 'Rakefile', "\n\ndefault_tasks = []\n\ntask default: default_tasks\n"
end

step 'Remove turbolinks support by default' do
  gsub_file 'app/assets/javascripts/application.js', %r{^//= require turbolinks$.}m, ''
end

additional_application_settings = <<-EOS
# configure asset hosts for controllers + mailers
    asset_host = "\#{ENV['DEFAULT_URL_PROTOCOL']}://\#{ENV['DEFAULT_URL_HOST']}"
    config.action_controller.asset_host = asset_host
    config.action_mailer.asset_host = asset_host

    # configure url helpers to use the options from env
    default_url_options = {
      host: ENV['DEFAULT_URL_HOST'],
      protocol: ENV['DEFAULT_URL_PROTOCOL']
    }
    #{app_name.camelize}::Application.routes.default_url_options = default_url_options
    config.action_mailer.default_url_options = default_url_options

    # use SSL, use Strict-Transport-Security, and use secure cookies
    config.force_ssl = (ENV['DEFAULT_URL_PROTOCOL'] == 'https')
EOS

step 'Configure application route builders' do
  environment additional_application_settings
end

step 'Configure application default timezone' do
  environment "config.time_zone = 'Central Time (US & Canada)'"
end

step 'Add lib/autoloaded to autoload_paths' do
  create_file 'lib/autoloaded/.gitkeep', ''
  environment "config.autoload_paths << config.root.join('lib', 'autoloaded')"
end

bundler_groups_applicationrb = <<-EOS

# Delay requiring debug group until dotenv-rails has been required
# which loads the necessary ENV variables
Bundler.require(:debug) if %w{ development test }.include?(Rails.env) && ENV['BUNDLER_INCLUDE_DEBUG_GROUP'] == 'true'
EOS

env_bundler_include_debug_group = <<-EOS
# enable debug gems in development/test mode
BUNDLER_INCLUDE_DEBUG_GROUP=true

EOS
step 'Add debug Bundler group' do
  install_gem 'pry-remote', group: :debug

  append_to_file '.env', env_bundler_include_debug_group
  insert_into_file 'config/application.rb', bundler_groups_applicationrb, after: /Bundler\.require.*\n/
end

step 'Disable config.assets.debug in development environment' do
  comment_lines 'config/environments/development.rb', /config.assets.debug = true/
end

staging = <<-EOS
# Based on production defaults
require Rails.root.join('config/environments/production')

# customize and override production settings here
#{app_name.camelize}::Application.configure do
end
EOS

step 'Add staging environment' do
  create_file 'config/environments/staging.rb', staging
end

vagrantfile = <<-EOS
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # All Vagrant configuration is done here. The most common configuration
  # options are documented and commented below. For a complete reference,
  # please see the online documentation at vagrantup.com.

  # Every Vagrant virtual environment requires a box to build off of.
  config.vm.box = "precise64"

  # The url from where the 'config.vm.box' box will be fetched if it
  # doesn't already exist on the user's system.
  config.vm.box_url = "http://files.vagrantup.com/precise64.box"

  # Boot with a GUI so you can see the screen. (Default is headless)
  # config.vm.boot_mode = :gui

  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--memory", "2048"]
    v.customize ["modifyvm", :id, "--cpus", "2"]
  end

  # Assign this VM to a host-only network IP, allowing you to access it
  # via the IP. Host-only networks can talk to the host machine as well as
  # any other machines on the same network, but cannot be accessed (through this
  # network interface) by any external networks.
  # config.vm.network :hostonly, "192.168.33.10"

  # Assign this VM to a bridged network, allowing you to connect directly to a
  # network using the host's network device. This makes the VM appear as another
  # physical device on your network.
  # config.vm.network :bridged

  # Forward a port from the guest to the host, which allows for outside
  # computers to access the VM, whereas host only networking does not.

  config.vm.network :forwarded_port, guest: 3000, host: 3000 # development server
  config.vm.network :forwarded_port, guest: 5432, host: 5432 # postgresql
  config.vm.network :forwarded_port, guest: 1080, host: 1080 # mailcatcher
  config.vm.network :forwarded_port, guest: 1025, host: 1025 # mailcatcher


  # Share an additional folder to the guest VM. The first argument is
  # an identifier, the second is the path on the guest to mount the
  # folder, and the third is the path on the host to the actual folder.
  # config.vm.share_folder "v-data", "/vagrant_data", "../data"

  # enable berkshelf for recipe management
  config.berkshelf.enabled = true

  # enable omnibus to manage latest chef version
  config.omnibus.chef_version = '11.6.2'

  # Enable provisioning with chef solo, specifying a cookbooks path, roles
  # path, and data_bags path (all relative to this Vagrantfile), and adding
  # some recipes and/or roles.
  VAGRANT_JSON = JSON.load(Pathname(__FILE__).dirname.join('.', 'chef', 'node.json').read)
  config.vm.provision :chef_solo do |chef|
    chef.roles_path     = "chef/roles"
    chef.data_bags_path = "chef/data_bags"
    chef.cookbooks_path = "chef/cookbooks"
    chef.log_level      = :debug

    # Cookbooks that require additional configuration go into
    # node.json and are loaded here
    chef.json           = VAGRANT_JSON
    VAGRANT_JSON.fetch('run_list', []).each do |recipe|
      chef.add_recipe(recipe)
    end
  end

  config.vm.provision :shell, path: 'bin/vm_rails_setup'
end
EOS

vagrant_gitignore = <<-EOS
# vagrant files
boxes/*
.vagrant
EOS

berksfile = <<-EOS
site :opscode

cookbook 'apt'
cookbook 'build-essential'
cookbook 'users'
cookbook 'sudo'
cookbook 'curl'
cookbook 'nginx'
cookbook 'postgresql', git: 'https://github.com/thegarage/postgresql'
cookbook 'git'
cookbook 'nodejs'
cookbook 'mailcatcher', git: 'https://github.com/thegarage/mailcatcher'
cookbook 'set_locale', git: 'https://github.com/thegarage/set_locale'
cookbook 'gemrc', git: 'https://github.com/wireframe/chef-gemrc'
cookbook 'ruby_build', git: 'https://github.com/fnichol/chef-ruby_build'
cookbook 'rbenv', git: 'https://github.com/fnichol/chef-rbenv'
EOS

databaseyml = <<-EOS
default: &default
  adapter: postgresql
  host: localhost
  username: 'postgres'

development:
  <<: *default
  database: #{app_name.parameterize}-dev

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test: &test
  <<: *default
  database: #{app_name.parameterize}-test

staging:
  <<: *default
  database: #{app_name.parameterize}-stage

production:
  <<: *default
  database: #{app_name.parameterize}-prod

EOS

chef_node_json = <<-EOS
{
  "build-essential": {},

  "postgresql": {
    "version": "9.2",
    "enable_pgdg_apt": true,
    "dir": "/etc/postgresql/9.2/main",
    "password": {
      "postgres": "postgres"
    },
    "client": {
      "packages": [
        "postgresql-client-9.2"
      ]
    },
    "server": {
      "packages": [
        "postgresql-9.2",
        "postgresql-server-dev-9.2"
      ]
    },
    "contrib": {
      "packages": [
        "postgresql-contrib-9.2"
      ]
    },
    "config": {
      "listen_addresses": "*",
      "lc_messages": "en_US.UTF-8",
      "lc_monetary": "en_US.UTF-8",
      "lc_numeric": "en_US.UTF-8",
      "lc_time": "en_US.UTF-8",
      "ssl_key_file": "/etc/ssl/private/ssl-cert-snakeoil.key",
      "ssl_cert_file": "/etc/ssl/certs/ssl-cert-snakeoil.pem"
    },
    "pg_hba": [
      {"type": "host", "db": "all", "user": "all", "addr": "127.0.0.1/32", "method": "trust"},
      {"type": "host", "db": "all", "user": "all", "addr": "0.0.0.0/0", "method": "trust"}
    ]
  },

  "rbenv": {
    "git_url": "https://github.com/sstephenson/rbenv.git",
    "user_installs": [
      {
        "user": "vagrant",
        "rubies": [
          "2.0.0-p247"
        ],
        "global": "2.0.0-p247",
        "gems": {
          "2.0.0-p247": [
            {"name": "bundler"}
          ]
        }
      }
    ]
  },

  "nodejs": {
    "version": "0.10.15",
    "install_method": "binary"
  },

  "run_list": [
    "recipe[set_locale]",
    "recipe[gemrc]",
    "recipe[apt]",
    "recipe[git]",
    "recipe[build-essential]",
    "recipe[curl]",
    "recipe[ruby_build]",
    "recipe[rbenv::user]",
    "recipe[nodejs]",
    "recipe[postgresql::server]",
    "recipe[postgresql::contrib]",
    "recipe[mailcatcher]"
  ]
}
EOS

vm_rails_setup = <<-EOS
#!/bin/bash

# Restart postgres, required for some reason for connecting from host
# the first time VM is built
sudo service postgresql restart

# setup clean rails environment
su vagrant -l <<ACTIONS
cd /vagrant
bundle install --local
bundle exec rake db:reset
bundle exec rake db:test:clone
sudo bundle exec foreman export upstart /etc/init --user vagrant
ACTIONS

/sbin/initctl emit provisioned
start app
EOS

step 'Setup Vagrant Virtual Machine' do
  create_file 'Vagrantfile', vagrantfile
  append_to_file '.gitignore', vagrant_gitignore

  create_file 'Berksfile', berksfile
  replace_file 'config/database.yml', databaseyml
  create_file 'chef/node.json', chef_node_json
  create_file 'bin/vm_rails_setup', vm_rails_setup

  create_file 'chef/roles/.gitkeep', ''
  create_file 'chef/data_bags/.gitkeep', ''
end

env_appserver_port = <<-EOS
# options for appserver
PORT=3000

EOS
step 'Adding Puma as default appserver' do
  install_gem 'foreman', group: :development
  install_gem 'puma'
  get_file 'bin/restart'
  chmod 'bin/restart', '755'
  get_file 'Procfile'

  append_to_file '.env', env_appserver_port
end

rspec_config_generators =  <<-EOS
config.generators do |g|
      g.view_specs false
      g.stylesheets = false
      g.javascripts = false
      g.helper = false
    end
EOS
rspec_base_config = <<-EOS

  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
EOS
rspec_extra_config = <<-EOS

  # enable controller tests to render views
  config.render_views

  # disable foo.should == bar syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

EOS

step 'Add Rspec' do
  remove_dir 'test/' unless ARGV.include?("-T")
  install_gem 'rspec-rails', group: [:development, :test]
  generate 'rspec:install'
  insert_into_file 'Rakefile', "default_tasks << :spec\n\n", before: "task default: default_tasks"
  environment rspec_config_generators
  insert_into_file 'spec/spec_helper.rb', rspec_base_config, after: /RSpec.configure do .*\n/i
  insert_into_file 'spec/spec_helper.rb', rspec_extra_config, after: /RSpec.configure do .*\n/i
  comment_lines 'spec/spec_helper.rb', /config.fixture_path.*/

  install_gem 'shoulda-matchers', group: :test

  install_gem 'factory_girl_rails', group: [:development, :test]
  install_gem 'factory_girl_rspec', group: :test
end

simplecov = <<-EOS
require 'simplecov'
SimpleCov.minimum_coverage 95
SimpleCov.start 'rails'
EOS
simplecov_gitignore = <<-EOS
# Simplecov files
coverage
EOS
step 'Add simplecov gem' do
  install_gem 'simplecov', require: false, group: :test
  prepend_to_file 'spec/spec_helper.rb', simplecov
  append_to_file '.gitignore', simplecov_gitignore
end

webrat_matcher_setup = <<-EOS
  # include extensions into rspec suite
  config.include Webrat::Matchers
EOS
step 'Add Webrat gem' do
  install_gem 'webrat', group: :test
  insert_into_file 'spec/spec_helper.rb', "require 'webrat'\n", after: "require 'rspec/autorun'\n"
  insert_into_file 'spec/spec_helper.rb', webrat_matcher_setup, after: "c.syntax = :expect\n  end\n\n"
end

step 'Add should_not gem' do
  install_gem 'should_not', group: :test
  insert_into_file 'spec/spec_helper.rb', "require 'should_not/rspec'\n", after: "require 'rspec/autorun'\n"
end

step 'Add webmock gem' do
  install_gem 'webmock', group: :test
  insert_into_file 'spec/spec_helper.rb', "require 'webmock/rspec'\n", after: "require 'rspec/autorun'\n"
end

vcr_setup = <<-EOS

VCR.configure do |c|
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
end
EOS
step 'Add vcr gem' do
  install_gem 'vcr', group: :test
  insert_into_file 'spec/spec_helper.rb', "require 'vcr'\n", after: "require 'rspec/autorun'\n"
  append_to_file 'spec/spec_helper.rb', vcr_setup
end

rubocopyml = <<-EOS
AllCops:
  Excludes:
    - 'db/schema.rb'
    - 'vendor/*'
    - 'chef/*'
    - 'bin/*'

# Allow longer lines
LineLength:
  Max: 190

# Allow methods longer than 10 lines of code
MethodLength:
  Max: 20

# Do not force classes/modules to have documentation
Documentation:
  Enabled: false

# Allow extend self for modules
ModuleFunction:
  Enabled: false

# disable cop for indentation of if/end blocks
# ex:
# foo = if false
#   'bar'
# else
#   'baz'
# end
EndAlignment:
  Enabled: false


# disable cop for indentation of body of if blocks
# ex:
# foo = if false
#   'bar'
# else
#   'baz'
# end
IndentationWidth:
  Enabled: false

EOS
create_file '.rubocop.yml', rubocopyml
rubocop_rake = <<-EOS
if defined?(Rubocop)
  require 'rubocop/rake_task'
  Rubocop::RakeTask.new do |task|
    task.patterns = ['--rails']
  end
  default_tasks << :rubocop
end

EOS
step 'Add Rubocop gem' do
  install_gem 'rubocop', group: [:development, :test]
  insert_into_file 'Rakefile', rubocop_rake, before: "task default: default_tasks"
end

jasmine_rake = <<-EOS
if defined?(JasmineRails)
  default_tasks << 'spec:javascript'
end

EOS
jasmine_gitignore = <<-EOS
# jasmine-rails files
spec/tmp
spec/javascripts/fixtures/generated/
EOS
jasmineyml = <<-EOS
# list of file expressions to include as specs into spec runner
# relative path from spec_dir
spec_files:
  - "**/*[Ss]pec.{js,coffee}"
EOS
step 'Add jasmine-rails gem' do
  install_gem 'jasmine-rails', group: [:development, :test]
  route "mount JasmineRails::Engine => '/specs' if defined?(JasmineRails)"
  insert_into_file 'Rakefile', jasmine_rake, before: "task default: default_tasks"
  append_to_file '.gitignore', jasmine_gitignore
  create_file 'spec/javascripts/support/jasmine.yml', jasmineyml
end

jshintrc = <<-EOS
{
  "bitwise": true,
  "camelcase": true,
  "curly": true,
  "eqeqeq": true,
  "forin": true,
  "immed": true,
  "indent": 2,
  "latedef": true,
  "newcap": true,
  "noarg": true,
  "noempty": true,
  "nonew": true,
  "quotmark": "single",
  "undef": true,
  "unused": true,
  "strict": true,
  "trailing": true,

  "browser": true,
  "jquery": true,
  "devel": false,

  "globals": {
    "_": false,
    "_V_": false,
    "afterEach": false,
    "beforeEach": false,
    "confirm": false,
    "context": false,
    "describe": false,
    "expect": false,
    "it": false,
    "jasmine": false,
    "JSHINT": false,
    "mostRecentAjaxRequest": false,
    "qq": false,
    "runs": false,
    "spyOn": false,
    "spyOnEvent": false,
    "waitsFor": false,
    "xdescribe": false,
    "loadFixtures": true,
    "FastClick": false,
    "_kmq": false
  }
}
EOS
jshintignore = <<-EOS
spec/tmp/**/*.js
vendor/**/*.js
coverage/**/*.js
tmp/**/*.js
EOS
jshintrb_rake = <<-EOS
if defined?(Jshintrb)
  require "jshintrb/jshinttask"
  Jshintrb::JshintTask.new :jshint do |t|
    options = JSON.load(File.read('.jshintrc'))
    globals = options.delete('globals')
    ignored = File.read('.jshintignore').split.collect {|pattern| FileList[pattern].to_a }.flatten
    files = Dir.glob('**/*.js')
    t.js_files = files
    t.exclude_js_files = ignored
    t.options = options
    t.globals = globals.keys
  end
  default_tasks << :jshint
end

EOS
step 'Add jshintrb gem' do
  install_gem 'jshintrb', group: [:development, :test]
  create_file '.jshintrc', jshintrc
  create_file '.jshintignore', jshintignore
  insert_into_file 'Rakefile', jshintrb_rake, before: "task default: default_tasks"
end

brakeman_task = <<-EOS
namespace :brakeman do

  desc "Run Brakeman"
  task :run, :output_files do |t, args|
    files = args[:output_files].split(' ') if args[:output_files]
    puts "Checking for security vulnerabilities..."
    tracker = Brakeman.run :app_path => ".", :output_files => files, :print_report => true
    if tracker.filtered_warnings.any?
      puts "Security vulnerabilities found!"
      exit 1
    end
  end
end

EOS
step 'Add brakeman:run Rake task' do
  install_gem 'brakeman'
  insert_into_file 'Rakefile', "default_tasks << 'brakeman:run'\n\n", before: "task default: default_tasks"
  lib 'tasks/brakeman.rake', brakeman_task
end

bundler_audit_rake = <<-EOS
namespace :bundler do
  desc 'audit Bundler Gemfile for vulnerable gems'
  task :audit do
    puts 'Checking Gemfile for vulnerable gems...'
    require 'English'
    output = `bundle-audit`
    puts output
    success = !!$CHILD_STATUS.to_i
    fail "bunder:audit failed" unless success
  end
end

EOS
step 'Add bundler:audit Rake task' do
  install_gem 'bundler-audit', group: :test, require: false
  lib 'tasks/bundler_audit.rake', bundler_audit_rake
  insert_into_file 'Rakefile', "default_tasks << 'bundler:audit'\n\n", before: "task default: default_tasks"
end

bundler_outdated_rake = <<-EOS
namespace :bundler do
  desc 'Generate report of outdated gems'
  task :outdated do
    puts "Generating report of outdated gems..."
    output = `bundle outdated`
    puts output
  end
end

EOS
step 'Add bundler:outdated Rake task' do
  lib 'tasks/bundler_outdated.rake', bundler_outdated_rake
  insert_into_file 'Rakefile', "default_tasks << 'bundler:outdated'\n\n", before: "task default: default_tasks"
end

newrelic_env = <<-EOS
# newrelic license key
# https://docs.newrelic.com/docs/ruby/ruby-agent-configuration
NEW_RELIC_LICENSE_KEY=#{newrelic_key}

EOS
newrelicyml = <<-EOS
#
# This file configures the New Relic Agent.  New Relic monitors
# Ruby, Java, .NET, PHP, and Python applications with deep visibility and low overhead.
# For more information, visit www.newrelic.com.


# Here are the settings that are common to all environments
common: &default_settings
  # ============================== LICENSE KEY ===============================

  # You must specify the license key associated with your New Relic
  # account.  This key binds your Agent's data to your account in the
  # New Relic service.
  # This should be configured via environmental variables
  # see .env file

  # Agent Enabled (Ruby/Rails Only)
  # Use this setting to force the agent to run or not run.
  # Default is 'auto' which means the agent will install and run only
  # if a valid dispatcher such as Mongrel is running.  This prevents
  # it from running with Rake or the console.  Set to false to
  # completely turn the agent off regardless of the other settings.
  # Valid values are true, false and auto.
  #
  # agent_enabled: auto

  # Application Name Set this to be the name of your application as
  # you'd like it show up in New Relic. The service will then auto-map
  # instances of your application into an "application" on your
  # dashboard page. If you want to map this instance into multiple
  # apps, like "AJAX Requests" and "All UI" then specify a semicolon
  # separated list of up to three distinct names, or a yaml list.
  # Defaults to the capitalized RAILS_ENV or RACK_ENV (i.e.,
  # Production, Staging, etc)
  #
  # Example:
  #
  #   app_name:
  #       - Ajax Service
  #       - All Services
  #
  app_name: #{app_name}

  # When "true", the agent collects performance data about your
  # application and reports this data to the New Relic service at
  # newrelic.com. This global switch is normally overridden for each
  # environment below. (formerly called 'enabled')
  monitor_mode: true

  # Developer mode should be off in every environment but
  # development as it has very high overhead in memory.
  developer_mode: false

  # The newrelic agent generates its own log file to keep its logging
  # information separate from that of your application. Specify its
  # log level here.
  log_level: info

  # Optionally set the path to the log file This is expanded from the
  # root directory (may be relative or absolute, e.g. 'log/' or
  # '/var/log/') The agent will attempt to create this directory if it
  # does not exist.
  # log_file_path: 'log'

  # Optionally set the name of the log file, defaults to 'newrelic_agent.log'
  # log_file_name: 'newrelic_agent.log'

  # The newrelic agent communicates with the service via https by default.  This
  # prevents eavesdropping on the performance metrics transmitted by the agent.
  # The encryption required by SSL introduces a nominal amount of CPU overhead,
  # which is performed asynchronously in a background thread.  If you'd prefer
  # to send your metrics over http uncomment the following line.
  # ssl: false

  #============================== Browser Monitoring ===============================
  # New Relic Real User Monitoring gives you insight into the performance real users are
  # experiencing with your website. This is accomplished by measuring the time it takes for
  # your users' browsers to download and render your web pages by injecting a small amount
  # of JavaScript code into the header and footer of each page.
  browser_monitoring:
      # By default the agent automatically injects the monitoring JavaScript
      # into web pages. Set this attribute to false to turn off this behavior.
      auto_instrument: true

  # Proxy settings for connecting to the New Relic server.
  #
  # If a proxy is used, the host setting is required.  Other settings
  # are optional. Default port is 8080.
  #
  # proxy_host: hostname
  # proxy_port: 8080
  # proxy_user:
  # proxy_pass:

  # The agent can optionally log all data it sends to New Relic servers to a
  # separate log file for human inspection and auditing purposes. To enable this
  # feature, change 'enabled' below to true.
  # See: https://newrelic.com/docs/ruby/audit-log
  audit_log:
    enabled: false

  # Tells transaction tracer and error collector (when enabled)
  # whether or not to capture HTTP params.  When true, frameworks can
  # exclude HTTP parameters from being captured.
  # Rails: the RoR filter_parameter_logging excludes parameters
  # Java: create a config setting called "ignored_params" and set it to
  #     a comma separated list of HTTP parameter names.
  #     ex: ignored_params: credit_card, ssn, password
  capture_params: false

  # Transaction tracer captures deep information about slow
  # transactions and sends this to the New Relic service once a
  # minute. Included in the transaction is the exact call sequence of
  # the transactions including any SQL statements issued.
  transaction_tracer:

    # Transaction tracer is enabled by default. Set this to false to
    # turn it off. This feature is only available at the Professional
    # and above product levels.
    enabled: true

    # Threshold in seconds for when to collect a transaction
    # trace. When the response time of a controller action exceeds
    # this threshold, a transaction trace will be recorded and sent to
    # New Relic. Valid values are any float value, or (default) "apdex_f",
    # which will use the threshold for an dissatisfying Apdex
    # controller action - four times the Apdex T value.
    transaction_threshold: apdex_f

    # When transaction tracer is on, SQL statements can optionally be
    # recorded. The recorder has three modes, "off" which sends no
    # SQL, "raw" which sends the SQL statement in its original form,
    # and "obfuscated", which strips out numeric and string literals.
    record_sql: obfuscated

    # Threshold in seconds for when to collect stack trace for a SQL
    # call. In other words, when SQL statements exceed this threshold,
    # then capture and send to New Relic the current stack trace. This is
    # helpful for pinpointing where long SQL calls originate from.
    stack_trace_threshold: 0.500

    # Determines whether the agent will capture query plans for slow
    # SQL queries.  Only supported in mysql and postgres.  Should be
    # set to false when using other adapters.
    # explain_enabled: true

    # Threshold for query execution time below which query plans will
    # not be captured.  Relevant only when `explain_enabled` is true.
    # explain_threshold: 0.5

  # Error collector captures information about uncaught exceptions and
  # sends them to New Relic for viewing
  error_collector:

    # Error collector is enabled by default. Set this to false to turn
    # it off. This feature is only available at the Professional and above
    # product levels.
    enabled: true

    # Rails Only - tells error collector whether or not to capture a
    # source snippet around the place of the error when errors are View
    # related.
    capture_source: true

    # To stop specific errors from reporting to New Relic, set this property
    # to comma-separated values.  Default is to ignore routing errors,
    # which are how 404's get triggered.
    ignore_errors: "ActionController::RoutingError,Sinatra::NotFound"

  # If you're interested in capturing memcache keys as though they
  # were SQL uncomment this flag. Note that this does increase
  # overhead slightly on every memcached call, and can have security
  # implications if your memcached keys are sensitive
  # capture_memcache_keys: true

# Application Environments
# ------------------------------------------
# Environment-specific settings are in this section.
# For Rails applications, RAILS_ENV is used to determine the environment.
# For Java applications, pass -Dnewrelic.environment <environment> to set
# the environment.

# NOTE if your application has other named environments, you should
# provide newrelic configuration settings for these environments here.

development:
  <<: *default_settings
  # Turn off communication to New Relic service in development mode (also
  # 'enabled').
  # NOTE: for initial evaluation purposes, you may want to temporarily
  # turn the agent on in development mode.
  monitor_mode: false

  # Rails Only - when running in Developer Mode, the New Relic Agent will
  # present performance information on the last 100 transactions you have
  # executed since starting the mongrel.
  # NOTE: There is substantial overhead when running in developer mode.
  # Do not use for production or load testing.
  developer_mode: true

  # Enable textmate links
  # textmate: true

test:
  <<: *default_settings
  # It almost never makes sense to turn on the agent when running
  # unit, functional or integration tests or the like.
  monitor_mode: false

# Turn on the agent in production for 24x7 monitoring. NewRelic
# testing shows an average performance impact of < 5 ms per
# transaction, you can leave this on all the time without
# incurring any user-visible performance degradation.
production:
  <<: *default_settings
  monitor_mode: true

# Many applications have a staging environment which behaves
# identically to production. Support for that environment is provided
# here.  By default, the staging environment has the agent turned on.
staging:
  <<: *default_settings
  monitor_mode: true
  app_name: #{app_name} (Staging)

EOS
step 'Add NewRelic gem' do
  install_gem 'newrelic_rpm'
  install_gem 'newrelic-rake'
  append_to_file '.env', newrelic_env
  create_file 'config/newrelic.yml', newrelicyml
end

honeybadger_env = <<-EOS
# honey badger account info
HONEY_BADGER_API_KEY=#{honeybadger_api_key}
EOS
honeybadgerrb = <<-EOS
  custom_env_filters = %w{
    HONEY_BADGER_API_KEY
    PGBACKUPS_URL
    HEROKU_POSTGRESQL_COBALT_URL
    DATABASE_URL
}

Honeybadger.configure do |config|
  config.api_key = ENV['HONEY_BADGER_API_KEY']
  config.params_filters.concat custom_env_filters
end
EOS
step 'Add Honeybadger gem' do
  install_gem 'honeybadger'
  append_to_file '.env', honeybadger_env
  initializer 'honeybadger.rb', honeybadgerrb
end

step 'Add Heroku 12factor gem' do
  install_gem 'rails_12factor', group: :production
end

travisyml = <<-EOS
language: ruby
bundler_args: --local --without development vm ct console debug
rvm:
  - ruby-2.0.0-p247
env:
  - BUNDLER_INCLUDE_DEBUG_GROUP=false

branches:
  except:
    - /build-.+-\d{4}-\d{2}-\d{2}-.*/

# create git tag to support quick rollback to last known good state
after_success:
  - git config --global user.email "builds@travis-ci.com"
  - git config --global user.name "Travis CI"
  - git buildtag

EOS
step 'Add Travis CI' do
  install_gem 'travis', group: :development
  create_file '.travis.yml', travisyml
  append_to_file '.travis.yml', travis_campfire_config if travis_campfire_config
end

step 'Add guard-rspec gem' do
  install_gem 'guard-rspec', group: :ct
  run_command 'guard init rspec'
  gsub_file 'Guardfile', /  # Capybara features specs.*\z/m, "end\n"
  run_command 'bundle binstubs guard'
end

rubocop_guardfile = <<'EOS'

guard :rubocop, all_on_start: false, cli: ['--rails'] do
  ignore(%r{db/schema\.rb})
  ignore(%r{vendor/.+\.rb})
  ignore(%r{chef/.+\.rb})
  watch(%r{.+\.rb$})
  watch(%r{(?:.+/)?\.rubocop\.yml$}) { |m| File.dirname(m[0]) }
end
EOS
step 'Add guard-rubocop gem' do
  install_gem 'guard-rubocop', group: :ct
  append_to_file 'Guardfile', rubocop_guardfile
end

step 'Add guard-jshintrb gem' do
  install_gem 'guard-jshintrb', group: :ct
  run_command 'guard init jshintrb'
end

jasmine_rails_guardfile = <<'EOS'

guard 'jasmine-rails', all_on_start: false do
  watch(%r{spec/javascripts/helpers/.+\.(js|coffee)})
  watch(%r{spec/javascripts/.+_spec\.(js\.coffee|js|coffee)$})
  watch(%r{app/assets/javascripts/(.+?)\.(js\.coffee|js|coffee)(?:\.\w+)*$}) { |m| "spec/javascripts/#{ m[1] }_spec.#{ m[2] }" }
end
EOS
step 'Add guard-jasmine-rails gem' do
  install_gem 'guard-jasmine-rails', group: :ct
  append_to_file 'Guardfile', jasmine_rails_guardfile
end

contributingmd = <<-EOS
# Test-Driven Development Workflow

## Step 1:  Create feature branch...

Always create a feature branch off of a freshly updated version of master.
Use the socialcast-git-extensions `start` command to simplify the process.

```
$ git start my-feature-branch
```

### Git Branching Protips&trade;
* Ensure branch stays up-to-date with latest changes merged into master (ex: `$ git update`)
* Use a descriptive branch name to help other developers (ex: fix-login-screen, api-refactor, payment-reconcile, etc)
* Follow [best practices](http://robots.thoughtbot.com/post/48933156625/5-useful-tips-for-a-better-commit-message) for git commit messages to communicate your changes.
* Only write the **minimal** amount of code necessary to accomplish the given task.
* Changes that are not directly related to the current feature should be cherry-picked into their own branch and merged separately than the current changeset.


## Step 2: Implement the requested change...
Use Test Driven Development to ensure that the feature has proper code coverage

**RED** - Write tests for the desired behavior...

**GREEN** - Write just enough code to get the tests to pass...

**REFACTOR** - Cleanup for clarity and DRY-ness...

### Testing Protips&trade;
* Every line of code should have associated unit tests.  If it's not tested, it's probably broken and you just don't know it yet...
* Follow [BetterSpecs.org](http://betterspecs.org/) as reference for building readable and maintainable unit tests.


## Step 3: Review changes with team members...
Submit pull request...Discuss...
Use the thegarage-gitx `reviewrequest` command to automate the process.

```
$ git reviewrequest
```

### Pull Request Protips&trade;
* Describe high level overview of the branch in pull request description
* Use screenshots (ex: skitch) or screencasts (ex: jing) to provide overview of changes
* Ensure that build is green (local build + travis-ci and/or deploy to staging environment)

### Questions to ask...
* Is there a simpler way to accomplish the task at hand?
* Are we solving the problems of today and not over engineering for the problems of tomorrow?


## Step 4: Sign-off and release

* Pull requests must be signed off by team leads before release (preferrably via :shipit: emoji)
* Smoketest all changes locally
* (optional) Smoketest changes in staging environment (via `git integrate staging`)
* Ensure that build is green (local build + travis-ci)/or deploy to staging environment)

Use socialcast-git-extensions `release` command to automate the process.

```
$ git release
```

## Step 5: Profit?
EOS

readmemd = <<-EOS
#{app_name}
===========

### Wondering where to go from here?

`vagrant up --provision`

Or, you can separately do `vagrant up` and `vagrant provision`. Same thing, split into two.

That'll get your VM running. This also has your Rails server already started- just check [http://localhost:3000/](http://localhost:3000/). If you check it sometime during development and it's down, shell into this folder and execute `touch tmp/restart.txt` to restart it.

You're ready to get started.

If you're a designer, feel free to put new views inside of `/app/views/static`.

If you're a developer, you're good to do whatever you want. When you're ready to hit production, don't forget to add your new NewRelic license to the `.env` file.

## And don't forget to update this!
EOS

step 'Add project documentation' do
  create_file 'CONTRIBUTING.md', contributingmd
  remove_file 'README.rdoc'
  replace_file 'README.md', readmemd
end

step 'Generate /static controller endpoint' do
  generate 'controller Static --no_helper'
  create_file 'app/views/static/.gitkeep', ''
  route "get 'static/:action' => 'static#:action' if Rails.env.development?"
end

step 'Cleanup rubocop validations' do
  gsub_file 'config/environments/test.rb', /config.static_cache_control = "public, max-age=3600"/, "config.static_cache_control = 'public, max-age=3600'"
  gsub_file 'config/routes.rb', /\n  \n/, ''
  gsub_file 'spec/spec_helper.rb', /"/, "'"
end

require 'securerandom'
secret_key_base = SecureRandom.hex(64)

env_secret_token = <<-EOS

# secret key used by rails for generating session cookies
# see config/initializers/secret_token.rb
SECRET_KEY_BASE=#{secret_key_base}
EOS

step 'Moving secret key to .env file' do
  gsub_file 'config/initializers/secret_token.rb', / =.*/, " = ENV['SECRET_KEY_BASE']"
  append_to_file '.env', env_secret_token
end

smtp_env = <<-EOS
#SMTP settings
SMTP_PORT=1025
SMTP_SERVER=localhost
EOS
smtp_applicationrb = <<-EOS
config.action_mailer.smtp_settings = {
      port: ENV['SMTP_PORT'],
      address: ENV['SMTP_SERVER']
    }
EOS
email_spec_matcher_setup = <<-EOS
  config.include EmailSpec::Helpers
  config.include EmailSpec::Matchers
EOS
step 'Implementing full e-mail support' do
  install_gem 'valid_email'
  install_gem 'email_spec', group: :test
  install_gem 'email_preview'
  append_to_file '.env', smtp_env
  environment smtp_applicationrb
  insert_into_file 'spec/spec_helper.rb', "require 'email_spec'\n", after: "require 'rspec/autorun'\n"
  insert_into_file 'spec/spec_helper.rb', email_spec_matcher_setup, after: "# include extensions into rspec suite\n"
end

step 'Finalize initial project' do
  run_command 'bundle install --local'
  git :init
  git add: '.'
  git commit: '-a -m "Initial checkin.  Built by thegarage-template Rails Generator"'
end
