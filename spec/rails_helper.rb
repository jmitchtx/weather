# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?

require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

# Developer Note: This file sets up the RSpec testing environment for a Rails app.
# It ensures the app runs in 'test' mode, loads the Rails environment, and configures
# RSpec to work with Rails-specific features like controllers and models.

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
# Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Developer Note: Uncomment the line above if you have support files in spec/support/
# that need to be loaded (e.g., custom matchers or helpers). For the weather app,
# you might add stubs or helpers here for mocking API responses if not using WebMock.

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Developer Note: This ensures the test database schema matches your migrations.
# For the weather app, this is less critical since it relies on external APIs rather
# than a database, but keep it if you add models later.

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # Developer Note: These settings are for ActiveRecord. Since the weather app
  # primarily uses external APIs (OpenStreetMap and weather.gov), you could disable
  # transactional fixtures or ActiveRecord support if no database is involved.

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/7-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Developer Note: `infer_spec_type_from_file_location!` is key for the weather app.
  # It allows `spec/controllers/weather_controller_spec.rb` to automatically use
  # controller test helpers like `get` and `response`.
end

require 'webmock/rspec'

# Developer Note: WebMock is included to stub external HTTP requests, which is
# critical for testing the weather app since it relies on Nominatim (geocoding)
# and weather.gov (forecast) APIs. This prevents real API calls during tests.

RSpec.configure do |config|
  config.before(:each) do
    # Stub Nominatim geocoding API
    WebMock.stub_request(:any, /nominatim.openstreetmap.org/).to_return(
      status: 200,
      body: "[]",
      headers: { 'Content-Type' => 'application/json' }
    )

    # Stub weather.gov points API
    WebMock.stub_request(:any, /api.weather.gov/).to_return(
      status: 200,
      body: '{"properties": {"periods": []}}',
      headers: { 'Content-Type' => 'application/json' }
    )

    # Stub forecast URL (specific forecast endpoint)
    WebMock.stub_request(:any, /forecast_url/).to_return(
      status: 200,
      body: '{"properties": {"periods": []}}',
      headers: { 'Content-Type' => 'application/json' }
    )

    # Developer Note: These stubs provide default empty responses for external APIs.
    # In your controller specs, override these stubs with specific responses to test
    # different scenarios (e.g., valid geocoding, forecast data with "Tonight").
    # Example: WebMock.stub_request(:get, /nominatim.openstreetmap.org/).to_return(body: '[{"lat": "40.71", "lon": "-74.01"}]')
  end
end

# Developer Note: To test the WeatherController effectively:
# 1. Write specs in `spec/controllers/weather_controller_spec.rb`.
# 2. Use WebMock to stub API responses with realistic data (e.g., periods with "Tonight").
# 3. Test edge cases like empty responses, invalid addresses, or API errors.
# 4. Verify caching behavior by checking `@from_cache` and Rails.cache interactions.
