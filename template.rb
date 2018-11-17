def apply_template
  customize_gems
  add_welcome_page
  customize_database

  configure_heroku if yes?("Create new heroku instance?")

  configure_gitlab if yes?("Create new repo on Gitlab?")
end

def set_gitlab_username
  @gitlab_username = ask("What is your username for Gitlab?", default: "stephaneliu")
end

def customize_gems
  say "Customizing gems"

  gem "awesome_print"
  gem "bootstrap", "~>4.1.0"
  gem "devise"
  gem "font-awesome-rails"
  gem "haml-rails"
  gem "jquery-rails"
  gem "pg"
  gem "rack-timeout"

  gem_group :development do
    gem "annotate"
    gem "better_errors"
    gem "foreman"
    gem "guard"
    gem "guard-brakeman", require: false
    gem "guard-ctags-bundler"
    gem "guard-reek"
    gem "guard-rspec"
    gem "guard-rubocop"
    gem "html2haml"
    gem "hub"
    gem "meta_request"
    gem "pronto"
    gem "pronto-brakeman", require: false
    gem "pronto-haml", require: false
    gem "pronto-reek", require: false
    gem "pronto-rubocop", require: false
    gem "pronto-simplecov", require: false
    gem "rails_layout"
    gem "rubocop"
    gem "spring"
    gem "spring-commands-rspec"
    gem "spring-watcher-listen", "~> 2.0.0"
    gem "terminal-notifier"
    gem "terminal-notifier-guard"
    gem "web-console", ">= 3.3.0"
  end

  gem_group :test do
    gem "capybara", "~> 2.13"
    gem "factory_bot_rails"
    gem "faker"
    gem "rspec_junit_formatter" # translate for circle-ci
    gem "pry-rails"
    gem "rspec-rails"
    gem "selenium-webdriver" # system test using selenium_chrome_headless
    gem "shoulda-matchers", "4.0.0.rc1"
    gem "rails-controller-testing" # dependency of shoulda-matchers
    gem "simplecov"
    gem "test-prof"
  end

  gem_group :development, :test do
    gem "rubocop-rspec"
  end

  run "bundle install"

  # setup rspec
  generate "rspec:install"
  generate "devise:install"
  generate "annotate:install"

  pronto_config = <<-EOL
verbose: false
  EOL

  create_file ".pronto.yml", pronto_config

  simplecov_config = <<-EOL
require 'simplecov'

if ENV['COVERAGE'] == 'true'
  SimpleCov.start 'rails' do
    minimum_coverage 90
    maximum_coverage_drop 5

    add_filter do |source|
      source.lines.count < 8
    end
  end
end
  EOL

  prepend_to_file "spec/spec_helper.rb", simplecov_config

  uncomment_lines("spec/spec_helper.rb", /disable_monkey_patching!/)

  reek_config = <<-EOL
"app/controllers":
  IrresponsibleModule:
    enabled: false
  NestedIterators:
    max_allowed_nesting: 2
  UnusedPrivateMethod:
    enabled: false
  InstanceVariableAssumption:
    enabled: false
"app/helpers":
  IrresponsibleModule:
    enabled: false
  UtilityFunction:
    enabled: false
"app/mailers":
  InstanceVariableAssumption:
    enabled: false
  EOL

  create_file ".reek", reek_config

  # Setup shoulda matchers
  shoulda_matchers = <<-EOL
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
  EOL

  create_file "spec/support/shoulda_matchers.rb", shoulda_matchers

  procfile = <<-EOL
web: bundle exec puma -C config/puma.rb
  EOL

  create_file "Procfile", procfile

  puma_config = <<-EOL
# frozen_string_literal: true

workers_count = Integer(ENV.fetch('WEB_CONCURRENCY') { 2 })
threads_count = ENV.fetch('RAILS_MAX_THREADS') { 5 }

workers workers_count
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV.fetch('PORT')      { 3000 }
environment ENV.fetch('RAILS_ENV') { 'development' }

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
  EOL

  remove_file "config/puma.rb"
  create_file "config/puma.rb", puma_config

  create_file ".ruby-version", "ruby-#{RUBY_VERSION}"

  guard_setup = <<-EOL
# frozen_string_literal: true

group :red_green_refactor, halt_on_fail: true do
  rspec_options = {
    cmd: 'bin/rspec -f doc',
    run_all: {
      cmd: 'COVERAGE=true bin/rspec -f doc'
    },
    all_after_pass: true
  }

  guard :rspec, rspec_options do
    require "guard/rspec/dsl"
    dsl = Guard::RSpec::Dsl.new(self)

    # RSpec files
    rspec = dsl.rspec

    watch(rspec.spec_helper)  { rspec.spec_dir }
    watch(rspec.spec_support) { rspec.spec_dir }
    watch(rspec.spec_files)

    # Ruby files
    ruby = dsl.ruby

    dsl.watch_spec_files_for(ruby.lib_files)

    # Rails files
    rails = dsl.rails(view_extensions: %w(erb haml slim))
    dsl.watch_spec_files_for(rails.app_files)
    dsl.watch_spec_files_for(rails.views)

    watch(rails.controllers) do |m|
      [
        rspec.spec.call("routing/\#{m[1]}_routing"),
        rspec.spec.call("controllers/\#{m[1]}_controller"),
        rspec.spec.call("acceptance/\#{m[1]}")
      ]
    end

    # Rails config changes
    watch(rails.spec_helper)    { rspec.spec_dir }
    watch(rails.routes)         { "\#{rspec.spec_dir}/routing" }
    watch(rails.app_controller) { "\#{rspec.spec_dir}/controllers" }

    # Capybara features specs
    watch(rails.view_dirs) { |m| rspec.spec.call("features/\#{m[1]}") }
    watch(rails.layouts)   { |m| rspec.spec.call("features/\#{m[1]}") }

    # Turnip features and steps
    watch(%r{^spec/acceptance/(.+)\.feature$})
    watch(%r{^spec/acceptance/steps/(.+)_steps\.rb$}) do |m|
      Dir[File.join("**/\#{m[1]}.feature")][0] || "spec/acceptance"
    end
  end

  rubocop_options = {
    all_on_start: false,
    cli: '--rails --parallel',
    # keep_failed: true,
  }

  guard :rubocop, rubocop_options do
    watch(%r{.+\.rb$})
    watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { |m| File.dirname(m[0]) }
  end

  brakeman_options = {
    run_on_start: true,
    quiet: true
  }

  guard 'brakeman', brakeman_options do
    watch(%r{^app/.+\.(erb|haml|rhtml|rb)$})
    watch(%r{^config/.+\.rb$})
    watch(%r{^lib/.+\.rb$})
    watch('Gemfile')
  end
end
  EOL

  create_file "Guardfile", guard_setup

  run "bundle exec spring binstub --all"

  git_ignore = <<-EOL
gems.tags
tags
./coverage
./.env
./config/initializers/*
  EOL

  append_to_file ".gitignore", git_ignore

  rails_command "db:create"

  rubocop_config = <<-EOL
require:
  - 'rubocop-rspec'
  - 'test_prof/rubocop'

AllCops:
  Exclude:
    - 'db/schema.rb'

FrozenStringLiteralComment:
  Enabled: true
  EnforcedStyle: 'when_needed'

Metrics/LineLength:
  Exclude:
    - 'Gemfile'
    - 'config/initializers/*'
    - 'db/seeds.rb'
  Max: 100

Metrics/BlockLength:
  Exclude:
    - 'Gemfile'
    - 'Guardfile'
    - 'lib/tasks/auto_annotate_models.rake'
    - 'spec/**/*.rb'

MultilineOperationIndentation:
  EnforcedStyle: 'indented'

Naming/HeredocDelimiterNaming:
  Enabled: false

Naming/VariableNumber:
  EnforcedStyle: 'snake_case'

Rails:
  Enabled: true

RSpec/DescribeClass:
  Exclude:
    - 'spec/views/**/*'
    - 'spec/routing/*'
    - 'spec/features/**/*'

RSpec/ExampleLength:
  Exclude:
    - 'spec/features/**/*'

RSpec/MultipleExpectations:
  Max: 2
  Exclude:
    - 'spec/features/**/*'

RSpec/NestedGroups:
  Max: 3

StringLiterals:
  Enabled: false

Style/Documentation:
  Exclude:
    - 'app/controllers/application_controller.rb'
    - 'app/helpers/application_helper.rb'
    - 'app/mailers/application_mailer.rb'
    - 'app/models/application_record.rb'
    - 'bin/*'
    - 'build/**/*'
    - 'config/**/*'
    - 'config/application.rb'
    - 'db/**/*'
    - 'deploy/**/*'
    - 'doc/**/*'
    - 'docker/**/*'
    - 'Gemfile'
    - 'Guardfile'
    - 'lib/tasks/*'
    - 'script/**/*'
    - 'spec/**/*'
    - 'test/**/*'
    - 'vendor/**/*'
    - !ruby/regexp /old_and_unused\.rb$/

Style/MixinUsage:
  Exclude:
    - 'bin/setup'
    - 'bin/update'

Style/PercentLiteralDelimiters:
  Exclude:
    - 'Guardfile'

Style/RegexpLiteral:
  Exclude:
    - 'Guardfile'

Style/StringLiterals:
  EnforcedStyle: "double_quotes"
  Exclude:
    - 'Guardfile'
  EOL

  create_file ".rubocop.yml", rubocop_config

  create_file "README"

  run "bundle exec rubocop --auto-correct --format simple"

  git :init
  git add: "."
  git commit: '-m "Initial commit."'

  run "direnv allow"

  run "spring stop"

  generator_configs = <<-EOL
      config.generators do |g|
        g.assets              false
        g.helper              false
        g.test_framework      :rspec, fixture: true
        g.view_specs          false
        g.fixture_replacement :factory_bot, dir: "spec/factories"
        g.helper              false
        g.template_engine     :haml
        g.stylesheets         false
      end
  EOL

  inject_into_class "config/application.rb", "Application", generator_configs

  git add: "."
  git commit: '-m "Customize gems"'
end

def add_welcome_page
  say "Adding welcome page"

  generate "controller welcome"
  welcome = <<-EOL
%h1 Welcome
%p
  Time now
  = Time.now
  to strike, while the iron is hot
  EOL

  create_file "app/views/welcome/index.html.haml", welcome

  route = <<-EOL
# frozen_string_literal: true

Rails.application.routes.draw do
  root 'welcome#index'
end
  EOL

  remove_file "config/routes.rb"
  create_file "config/routes.rb", route

  run_rubocop_autocorrect

  git add: "."
  git commit: '-m "Add welcome"'
end

def customize_database
  database_config = <<-EOL
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("PGHOST") { "localhost" } %>
  username: <%= ENV.fetch("PGUSER") { ENV["USER"] } %>

development:
  <<: *default
  database: #{app_name}_development

test:
  <<: *default
  database: #{app_name}_test

# As with config/secrets.yml, you never want to store sensitive information,
# like your database password, in your source code. If your source code is
# ever seen by anyone, they now have access to your database.
#
# Instead, provide the password as a unix environment variable when you boot
# the app. Read http://guides.rubyonrails.org/configuring.html#configuring-a-database
# for a full rundown on how to provide these environment variables in a
# production deployment.
#
# On Heroku and other platform providers, you may have a full connection URL
# available as an environment variable. For example:
#
#   DATABASE_URL="mysql2://myuser:mypass@localhost/somedatabase"
#
# You can use this database configuration with:
#
#   production:
#     url: <%= ENV['DATABASE_URL'] %>
#
production:
  <<: *default
  database: #{app_name}_production
  password: <%= ENV['#{app_name}_DATABASE_PASSWORD'] %>
  EOL

  remove_file "config/database.yml"
  create_file "config/database.yml", database_config

  git add: "."
  git commit: '-m "Customize database"'
end

def configure_heroku
  create_file "bin/setup_heroku" do
    <<-EOL
set -e

apt-get update -yq
apt-get install apt-transport-https python3-software-properties -y

curl https://cli-assets.heroku.com/install.sh | sh

gem install dpl
    EOL
  end

  chmod "bin/setup_heroku", 0755

  @heroku_project_name = ask("Name of Heroku project?", default: app_name)

  while non_compliant_heroku_app_name?(@heroku_project_name)
    say "Heroku project names must start with a letter and can only contain lowercase letters, " \
      "numbers, and dashes."

    @heroku_project_name = ask("Name of Heroku project?", default: heroku_compliant_name)
  end

  say "Creating staging env on Heroku"

  run "heroku create #{@heroku_project_name}-staging"

  say "Adding master key to heroku staging instance"
  run "heroku config:set -a #{@heroku_project_name}-staging "\
    "RAILS_MASTER_KEY=$(cat config/master.key)"

  say "Creating production env on Heroku"
  run "heroku create #{@heroku_project_name}-production"
  say "Adding master key to heroku production instance"
  run "heroku config:set -a #{@heroku_project_name}-production "\
    "RAILS_MASTER_KEY=$(cat config/master.key)"

  say "Enabling encryption master key in production environment", :yellow
  uncomment_lines "config/environments/production.rb", /require_master_key/

  git push: "heroku master"
  run "heroku ps:scale web=1" # free tier

  say "Adding papertrail logging/alerting - free tier", :yellow
  run "heroku addons:create papertrail:choklad -a #{@heroku_project_name}-production"
  say "Opening papertrail dashboard", :yellow
  run "heroku addons:open papertrail -a #{@heroku_project_name}-production"

  run "heroku open"

  git add: "."
  git commit: '-m "Configure heroku"'
end

def configure_gitlab
  set_gitlab_username

  git remote: "add origin git@gitlab.com:#{@gitlab_username}/#{app_name}.git"
  git push: "origin master"
  git branch: "--set-upstream-to=origin/master master"

  configure_gitlab_ci
end

def configure_gitlab_ci
  create_file "config/database.yml.gitlab" do
    <<-EOL
test:
  adapter: postgresql
  encoding: unicode
  pool: 5
  timeout: 5000
  host: postgres
  username: runner
  password: ""
  database: test_db
    EOL
  end

  # CI/CD
  create_file ".gitlab-ci.yml" do
    <<-EOL
image: "ruby:#{RUBY_VERSION}"

services:
  - postgres:latest

.cache_bundler: &cache_bundler
  cache:
    untracked: true
    key: "$CI_BUILD_REF_NAME"
    paths:
      - cache/bundle/

.setup_test_env: &setup_test_env
  before_script:
    # Check installation
    - ruby -v
    - which ruby

    # Install dependencies
    - apt-get update -qq && apt-get install -y -qq nodejs cmake

    # Project Setup
    - gem install bundler --no-ri --no-rdoc
    - bundle install --path=cache/bundler --jobs $(nproc) "${FLAGS[@]}"
    - cp config/database.yml.gitlab config/database.yml
    - bundle exec rails db:create RAILS_ENV=test
    - bundle exec rails db:schema:load RAILS_ENV=test

variables:
  POSTGRES_DB: test_db
  POSTGRES_USER: runner
  POSTGRES_PASSWORD: ""
  BUNDLE_PATH: vendor/bundle
  DISABLE_SPRING: 1

stages:
  - test
  - lint
  - deploy

test:
  stage: test
  <<: *cache_bundler
  <<: *setup_test_env
  script:
    - RAILS_ENV=test bundle exec rspec

Pronto:
  stage: lint
  <<: *cache_bundler
  <<: *setup_test_env
  allow_failure: true
  script:
    - bundle exec pronto run -c=origin/master --exit-code

Deploy Staging:
  stage: deploy
  retry: 2
  environment:
    name: staging
    url: https://#{@heroku_project_name}-staging.herokuapp.com
  script:
    - ./bin/setup_heroku
    - dpl --provider=heroku --app=#{@heroku_project_name}-staging --api-key=$HEROKU_API_KEY
    - heroku run rake db:migrate --exit-code --app #{@heroku_project_name}-staging
  only:
    - master

Deploy Production:
  stage: deploy
  retry: 2
  environment:
    name: production
    url: https://#{@heroku_project_name}-production.herokuapp.com
  script:
    - ./bin/setup_heroku
    - dpl --provider=heroku --app=#{@heroku_project_name}-production --api-key=$HEROKU_API_KEY
    - heroku run rake db:migrate --exit-code --app #{@heroku_project_name}-production
  only:
    - tags
    EOL
  end

  run("open https://gitlab.com/#{@gitlab_username}/#{app_name}/settings/ci_cd")
  run("open https://dashboard.heroku.com/account")
  say("Reminder - create HEROKU_API_KEY variable for project. Web pages have been opened.",
      :red, :bold)

  git add: "."
  git commit: '-m "Add gitlab ci"'
  git push: "origin master"

  run_rubocop_autocorrect
  run "bundle exec rspec spec" # should have no errors
end

def run_rubocop_autocorrect
  run "bundle exec rubocop --auto-correct --format simple"
end

def non_compliant_heroku_app_name?(name)
  name !~ /^[a-z][[a-z]|\d|-|[^_]]{3,}$/
end

def heroku_compliant_name
  app_name
    .downcase
    .gsub(/^\d-?/, "one-")    # replace names starting with number with 'one'
    .gsub(/[[\W|_]-?]/, "-")  # replace non-word char and underscores with hyphen
    .gsub(/-{2,}/, "-")       # replace repeating hyphens with one hyphen
end

apply_template
