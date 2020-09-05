def apply_template
  validate_dependencies
  initial_commit

  customize_gems
  configure_rspec
  configure_devise
  configure_annotate
  configure_reek
  configure_puma
  configure_guard
  configure_spring
  configure_git
  configure_rubocop
  configure_haml_lint
  configure_prettier
  configure_rails_defaults

  create_database
  create_readme

  add_welcome_page
  customize_database
  # setup_bootstrap
end

def validate_dependencies
  return true if(system("which gh"))

  say "gh (Github CLI) not installed"
  exit 1
end

def initial_commit
  git :init
  commit("Chore: Initial commit")
end

def customize_gems
  say "Customizing gems"

  gem "awesome_print"
  gem "bootstrap", "~>4.5"
  gem "devise", "~> 4.7", ">= 4.7.1"
  gem "font-awesome-sass", "~> 5.13"
  gem "haml-rails", "~> 2.0"
  gem "pg"
  gem "rack-timeout"

  gem_group :development do
    gem "annotate"
    gem "annotate_gem"
    gem "better_errors"
    gem "guard"
    gem "guard-brakeman", require: false
    gem "guard-reek"
    gem "guard-rspec"
    gem "guard-rubocop"
    gem "html2haml"
    gem "meta_request"
    gem "prettier"
    gem "rails_layout"
    gem "rubocop"
    gem "spring"
    gem "spring-commands-rspec"
    gem "spring-watcher-listen"
    gem "terminal-notifier"
    gem "terminal-notifier-guard"
    gem "web-console", ">= 3.3.0"
    gem 'guard-haml_lint'
    gem 'guard-process'
  end

  gem_group :test do
    # gem "capybara", "~> 2.13"
    gem "factory_bot_rails"
    gem "faker"
    gem "rspec-rails"
    gem "selenium-webdriver" # system test using selenium_chrome_headless
    gem "shoulda-matchers", "~> 4.4"
    gem "simplecov", require: false
    gem "test-prof"
  end

  gem_group :development, :test do
    gem "pry-byebug"
    gem "pry-rails"
    gem "rubocop-rspec"
  end

  run "bundle install && bundle update"
  run "annotate_gem"
end

def configure_rspec
  generate "rspec:install"

  simplecov_config = <<~EOL

    if ENV['COVERAGE'] == 'true'
      require 'simplecov'

      SimpleCov.start 'rails' do
        minimum_coverage 95
        maximum_coverage_drop 1

        # https://github.com/simplecov-ruby/simplecov#branch-coverage-ruby--25
        enable_coverage :branch

        min_line_count = proc { |source_file| source_file.lines.count < 11 }
        add_filter [min_line_count, /vendor/]

        add_group "Commands", "app/commands"
        add_group "Crons", "app/crons"
        add_group "Decorators", "app/decorators"
        add_group "Finders", "app/finders"
        add_group "Forms", "app/forms"
        add_group "Jobs", "app/jobs"
        add_group "Nulls", "app/nulls"
        add_group "Policies", "app/policies"
        add_group "Presenters", "app/presenters"
        add_group "Queries", "app/queries"
        add_group "Services", "app/services"
        add_group "Validators", "app/validators"
        add_group "Long files" { |file| file.lines.count > 300 }
      end
    end
  EOL

  prepend_to_file "spec/spec_helper.rb", simplecov_config
  uncomment_lines("spec/spec_helper.rb", /disable_monkey/)
  uncomment_lines("spec/spec_helper.rb", /filter_run_when_matching/)
  uncomment_lines("spec/spec_helper.rb", /example_status_persistence_file_path/)

  content = <<~EOL
    Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }\n\n
  EOL

  insert_into_file("spec/rails_helper.rb", content, before: "RSpec.configure do")

  configure_shoulda_matchers
  configure_factory_bot
end

def configure_shoulda_matchers
  shoulda_matchers = <<~EOL.strip
    Shoulda::Matchers.configure do |config|
      config.integrate do |with|
        with.test_framework :rspec
        with.library :rails
      end
    end
  EOL

  create_file "spec/support/shoulda_matchers.rb", shoulda_matchers
end

def configure_factory_bot
  factory_bot = <<~EOL.strip
    RSpec.configure { |config| config.include FactoryBot::Syntax::Methods }
  EOL

  create_file "spec/support/factory_bot.rb", factory_bot
end

def configure_devise 
  generate "devise:install"
end

def configure_annotate
  generate "annotate:install"

  append_to_file "Rakefile", "Annotate.load_tasks if Rails.env.development?"
end

def configure_reek
  reek_config = <<~EOL.strip
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
end

def configure_puma
  procfile = <<~EOL.strip
    web: bundle exec puma -C config/puma.rb
  EOL

  create_file "Procfile", procfile

  puma_config = <<-EOL
    # frozen_string_literal: true

    workers_count = Integer(ENV.fetch('WEB_CONCURRENCY', 2))
    threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)

    workers workers_count
    threads threads_count, threads_count

    preload_app!

    rackup      DefaultRackup
    port        ENV.fetch('PORT', 3000)
    environment ENV.fetch('RAILS_ENV', 'development')

    on_worker_boot do
      ActiveRecord::Base.establish_connection
    end

    # Allow puma to be restarted by `rails restart` command.
    plugin :tmp_restart
  EOL

  remove_file "config/puma.rb"
  create_file "config/puma.rb", puma_config
end

def configure_guard
  guard_setup = <<~EOL.strip
    # frozen_string_literal: true

    guard 'process', name: 'Webpacker', command: 'bin/webpack' do
      watch(%r{^app/javascript/\w+/*})
    end

    # Guard-HamlLint supports a lot options with default values:
    # all_on_start: true        # Check all files at Guard startup. default: true
    # haml_dires: ['app/views'] # Check Directories. default: 'app/views' or '.'
    # cli: '--fail-fast --no-color' # Additional command line options to haml-lint.
    guard :haml_lint, all_on_start: false do
      watch(%r{.+\.html.*\.haml$})
      watch(%r{(?:.+/)?\.haml-lint\.yml$}) { |m| File.dirname(m[0]) }
    end

    group :rgr, halt_on_fail: true do
      rspec_options = {
        cmd: 'bin/rspec -f doc --next-failure --color',
        run_all: {
          cmd: 'COVERAGE=true DISABLE_SPRING=true bin/rspec -f doc'
        },
        all_on_start: true,
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
        all_on_start: true,
        cli: '--parallel',
        keep_failed: true
      }

      guard :rubocop, rubocop_options do
        watch(%r{.+\.rb$})
        watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { |m| File.dirname(m[0]) }
      end

      guard 'reek' do
        watch(%r{.+\.rb$})
        watch('.reek')
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
end

def configure_spring
  run "bundle exec spring binstub --all"
end

def configure_git
  git_ignore = <<~EOL.strip
    .DS_Store
    gems.tags
    tags
    ./coverage
    ./.env
    ./config/initializers/*
  EOL

  append_to_file ".gitignore", git_ignore
end

def configure_rubocop
  rubocop_config = <<~EOL
    require:
      - 'rubocop-rspec'
      - 'test_prof/rubocop'

    AllCops:
      NewCops: enable
      Exclude:
        - 'bin/*'l
        - 'db/schema.rb'
        - 'node_modules/**/*'
        - 'vendor/**/*'

    Layout/LineLength:
      Exclude:
        - 'Gemfile'
        - 'config/initializers/*'
        - 'db/seeds.rb'
      Max: 100

    Layout/MultilineOperationIndentation:
      EnforcedStyle: 'indented'

    Metrics/BlockLength:
      Exclude:
        - 'Gemfile'
        - 'Guardfile'
        - 'lib/tasks/auto_annotate_models.rake'
        - 'spec/**/*.rb'

    Naming/HeredocDelimiterNaming:
      Enabled: false

    Naming/VariableNumber:
      EnforcedStyle: 'snake_case'

    Rails:
      Enabled: true

    RSpec/AggregateExamples:
      Enabled: true
      Include:
        - 'spec/**/*.rb'

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

    Style/Documentation:
      Exclude:
        - 'app/controllers/*'
        - 'app/forms/*'
        - 'app/helpers/application_helper.rb'
        - 'app/mailers/application_mailer.rb'
        - 'app/models/*'
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

    Style/FrozenStringLiteralComment:
      Enabled: true
      EnforcedStyle: 'always'

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
end

def configure_haml_lint
  haml_lint = <<~EOL.strip
    linters:
      FinalNewline:
        enabled: false
  EOL

  create_file ".haml-lint.yml", haml_lint
end

def configure_prettier
  prettierrc = <<~EOL.strip
    {
      "preferSingleQuotes": false,
      "printWidth": 100
    }
  EOL

  prettier_ignore = <<~EOL.strip
    db/schema.rb
    db/migrate/*
    coverage
    doc
    docker
    engines/**/db/schema.rb
    engines/**/db/migrate/*
    tmp
    vendor
  EOL

  create_file ".prettierrc", prettierrc 
  create_file ".prettierignore", prettier_ignore

  run "yarn add --dev prettier @prettier/plugin-ruby"
end

def create_readme
  create_file "README"
end

def configure_rails_defaults
  generator_configs = <<-EOL
    config.generators do |g|
      g.helper              false
      g.test_framework      :rspec, fixture: true
      g.view_specs          false
      g.fixture_replacement :factory_bot, dir: "spec/factories"
      g.helper              false
      g.template_engine     :haml
      g.stylesheet_engine   :sass
    end
  EOL

  application generator_configs
end

def create_database
  rails_command "db:create"
  rails_command "db:migrate"
end

def add_welcome_page
  say "Adding welcome page"

  run "spring stop"
  generate "controller welcome"
  welcome = <<~EOL.strip
    %h1 Welcome
    .jumbotron
      %h1.display-4 Welcome!
      %p.lead
        The time now is
        = Time.now
      %hr.my-4
      %p Strike while the iron is hot!
  EOL

  create_file "app/views/welcome/index.html.haml", welcome
  route "root 'welcome#index'"
end

def customize_database
  database_config = <<~EOL.strip
    default: &default
      adapter: postgresql
      encoding: unicode
      pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
      host: <%= ENV.fetch("PGHOST") { "localhost" } %>
      password: <%= ENV.fetch("PG_PASSWORD") { ENV['#{app_name}_DATABASE_PASSWORD'] } %>
      username: <%= ENV.fetch("PGUSER") { ENV["USER"] } %>

    development:
      <<: *default
      database: #{app_name}_development

    test:
      <<: *default
      database: #{app_name}_test

    production:
      <<: *default
      database: #{app_name}_production
      host: <%= ENV.fetch("PGHOST") { "localhost" } %>
  EOL

  remove_file "config/database.yml"
  create_file "config/database.yml", database_config

  commit("Chore: Customize database")
end
def setup_bootstrap
  say "Bootstrapping Bootstrap"
  setup_bootstrap_css
  setup_bootstrap_javascript
  setup_bootstrap_layout
end

def setup_bootstrap_css
  application_scss = <<~EOL.strip
    /*
    *= require_self
    *= require_tree .
    */
    // Custom bootstrap variables must be set or imported *before* bootstrap.
    @import "bootstrap";
    @import "font-awesome";
  EOL

  git rm: "app/assets/stylesheets/application.css"
  create_file "app/assets/stylesheets/application.scss", application_scss
end

def setup_bootstrap_javascript
  bootstrap_required_js = <<~EOL
    //= require jquery3
    //= require popper
    //= require bootstrap-sprockets

  EOL

  inject_into_file "app/assets/javascripts/application.js", \
    bootstrap_required_js, \
    before: "//= require_tree ."
end

def setup_bootstrap_layout
  application_layout = <<~EOL.strip
    !!!
    %html{ lang: 'en' }
      %head
        %title #{app_name}
        %meta{ charset: 'utf-8' }
        %meta{ name: 'viewport', content: "width=device-width, initial-scale=1, shrink-to-fit=no" }
        = csrf_meta_tags
        = csp_meta_tag
        = stylesheet_link_tag    'application', media: 'all', 'data-turbolinks-track': 'reload'
        = javascript_include_tag 'application', 'data-turbolinks-track': 'reload'

        %body
          .container-fluid
            = yield
  EOL

  git rm: "app/views/layouts/application.html.erb"
  create_file "app/views/layouts/application.html.haml", application_layout
end

def configure_heroku
  @heroku_project_name = app_name

  if non_compliant_heroku_app_name?(app_name)
    @heroku_project_name = ask("Name of Heroku project?", default: heroku_compliant_name)
  end

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

  commit("Chore: Configure heroku")
  git push: "heroku master"
  run "heroku ps:scale web=1" # free tier

  say "Adding papertrail logging/alerting - free tier", :yellow
  run "heroku addons:create papertrail:choklad -a #{@heroku_project_name}-production"
  say "Opening papertrail dashboard", :yellow
  run "heroku addons:open papertrail -a #{@heroku_project_name}-production"

  run "heroku open"
end

def configure_github
  # replace with (gh api repos/:owner/:repo).[:full_name].slice('/').first => stephaneliu
  @github_username = "stephaneliu" #ask("What is your username for Github?", default: "stephaneliu")
  run "gh repo create"
  configure_github_ci_cd

  run("open https://github.com/#{@github_username}/#{app_name}/settings/secrets")
  run("open https://dashboard.heroku.com/account")
  ask("Create a RAILS_MASTER_KEY, HEROKU_EMAIL, and HEROKU_API_KEY in browser (cat config/master.key | pbcopy). Hit ENTER to continue", default: "ENTER")

  commit("Chore: Add github CI/CD")
  git push: "--set-upstream origin master"
end

def configure_github_ci_cd
  create_file ".github/workflows/ci_cd.yml" do
    <<~EOL.strip
      name: Test and deploy

      on: [push, pull_request]

      jobs:
        lint:
          runs-on: ubuntu-latest

          steps:
            - name: Checkout repo
              uses: actions/checkout@v2

            - name: Install yarn
              uses: borales/actions-yarn@v2.0.0
              with:
                cmd: install

            - name: Run Prettier
              run: |
                sudo yarn install
                sudo yarn prettier --check '**/*.rb'

        rubocop:
          runs-on: ubuntu-latest

          steps:
            - name: Checkout repo
              uses: actions/checkout@v2

            - name: Setup Ruby
              uses: actions/setup-ruby@v1
              with:
                ruby-version: #{ENV.fetch("RUBY_VERSION") { "2.6.x" }}

            - name: Cache Bundler
              uses: actions/cache@v2
              with:
                path: vendor/bundle
                key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
                restore-keys: |
                  ${{ runner.os }}-gems-

            - name: Install Rubocop
              run: |
                gem install bundler
                bundle config path vendor/bundle
                bundle install --jobs 4 --retry 3

            - name: Run Rubocop
              env:
                RAILS_ENV: test
                RlAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
              run: |
                bundle exec rubocop

        test:
          runs-on: ubuntu-latest

          services:
            db:
              image: postgres:11@sha256:85d79cba2d4942dad7c99f84ec389a5b9cc84fb07a3dcd3aff0fb06948cdc03b
              ports: ['5432:5432']
              options: >-
                --health-cmd pg_isready
                --health-interval 10s
                --health-timeout 5s
                --health-retries 5
            redis:
              image: redis
              ports: ['6379:6379']
              options: --entrypoint redis-server

          steps:
            - name: Checkout repo
              uses: actions/checkout@v2

            - name: Setup Ruby
              uses: actions/setup-ruby@v1
              with:
                ruby-version: #{ENV.fetch("RUBY_VERSION") { "2.6.x" }}

            - name: Install yarn
              uses: borales/actions-yarn@v2.0.0
              with:
                cmd: install

            - name: Cache Bundler
              uses: actions/cache@v2
              with:
                path: vendor/bundle
                key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
                restore-keys: |
                  ${{ runner.os }}-gems-

            - name: Run tests
              env:
                PGUSER: postgres
                PG_PASSWORD: postgres
                REDIS_URL: redis://localhost:6379/0
                RAILS_ENV: test
                RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
              run: |
                sudo apt-get -yqq install libpq-dev
                gem install bundler
                bundle config path vendor/bundle
                bundle install --jobs 4 --retry 3
                bundle exec rails db:prepare
                bundle exec rspec spec

        deploy_staging:
          runs-on: ubuntu-latest

          needs: [lint, rubocop, test]
          if: github.ref == 'refs/heads/master'

          steps:
            - name: Checkout repo
              uses: actions/checkout@v2

            - name: Deploy #{@heroku_project_name}-stagging
              env:
                HEROKU_API_KEY: ${{ SECRETS.HEROKU_API_KEY }}
              run: |
                sudo apt-get -yqq install apt-transport-https python3-software-properties
                curl https://cli-assets.heroku.com/install.sh | sudo sh
                sudo gem install dpl
                sudo dpl --provider=heroku --app=#{@heroku_project_name}-staging --api-key=$HEROKU_API_KEY
                heroku run rake db:migrate --exit-code --app #{@heroku_project_name}-staging

        deploy_production:
          runs-on: ubuntu-latest

          needs: [lint, rubocop, test]
          if: startsWith(github.ref, 'refs/tags/v')

          steps:
            - name: Checkout repo
              uses: actions/checkout@v2

            - name: Deploy #{@heroku_project_name}-production
              env:
                HEROKU_API_KEY: ${{ SECRETS.HEROKU_API_KEY }}
              run: |
                sudo apt-get -yqq install apt-transport-https python3-software-properties
                curl https://cli-assets.heroku.com/install.sh | sudo sh
                sudo gem install dpl
                sudo dpl --provider=heroku --app=#{@heroku_project_name}-production --api-key=$HEROKU_API_KEY
                heroku run rake db:migrate --exit-code --app #{@heroku_project_name}-production
    EOL
  end
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

def commit(message)
  git add: "."
  git commit: "-m '#{message}'"
end

apply_template

after_bundle do
  configure_heroku
  configure_github

  say "Run rubocop"
  say "bundle exec rubocop --format simple --auto-correct", :green

  say "Run tests"
  say "bundle exec rspec", :green

  say "Run prettier"
  say "yarn prettier --write '**/*.rb'", :green

  commit "Chore: Apply custom Rails template"

  say "TODO: Remember to CLEAN UP GEMFILE", :red
end
