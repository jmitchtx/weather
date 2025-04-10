# Developer Note: This controller handles weather forecast requests for a given address.
# It integrates with external APIs (Nominatim for geocoding and weather.gov for forecasts)
# and uses Rails caching to reduce API calls. The forecast focuses on evening periods with
# highs derived from corresponding daytime periods.

class WeatherController < ApplicationController
  def index
    @address = params[:address]
    @weather_data = nil
    @from_cache = false

    # Developer Note: Only process if an address is provided via params.
    if @address.present?
      # Generate a unique cache key based on the address using MD5 hash.
      cache_key = "weather_#{Digest::MD5.hexdigest(@address)}"
      cached_data = Rails.cache.read(cache_key)

      # Check cache first unless 'force' param is present to bypass cache.
      if cached_data && params[:force].blank?
        @weather_data = cached_data
        @from_cache = true
      else
        # Developer Note: Chain of API calls: geocode -> get forecast URL -> fetch forecast.
        coordinates = geocode_address(@address)
        if coordinates
          forecast_url = get_forecast_url(coordinates[:lat], coordinates[:lon])
          Rails.logger.info("Forecast URL: #{forecast_url}")
          if forecast_url
            periods = get_weather_forecast(forecast_url)

            if periods
              @weather_data = extract_weather_data(periods)
              # Cache the result for 30 minutes to reduce API load.
              Rails.cache.write(cache_key, @weather_data, expires_in: 30.minutes)
            end
          end
        end
      end
    end

    # Developer Note: @weather_data is nil if any step fails (invalid address, API errors, etc.).
    # The view should handle this case (e.g., display an error message).
  end

  private

  def geocode_address(address)
    # Developer Note: Uses Nominatim (OpenStreetMap) to convert an address to lat/lon coordinates.
    encoded_address = URI.encode_www_form_component(address)
    url = "https://nominatim.openstreetmap.org/search?q=#{encoded_address}&format=json&limit=1"

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    # Set a custom User-Agent as required by Nominatim's usage policy.
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)
    data = JSON.parse(response.body)

    Rails.logger.info("Geocode response: #{data.inspect}")
    return nil if data.empty? # Return nil if no results found.

    Rails.logger.info("Geocode coordinates: #{data[0]['lat'].to_f}, #{data[0]['lon'].to_f}")
    # Round coordinates to 2 decimal places for simplicity.
    { lat: data[0]["lat"].to_f.round(2), lon: data[0]["lon"].to_f.round(2) }
  end

  def get_forecast_url(lat, lon)
    # Developer Note: Queries weather.gov's /points endpoint to get a forecast URL for the coordinates.
    url = "https://api.weather.gov/points/#{lat},#{lon}"
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)

    return nil if response.code != "200" # Return nil on non-200 responses (e.g., 404, 500).

    begin
      data = JSON.parse(response.body)
      data["properties"]["forecast"]
    rescue JSON::ParserError
      nil # Return nil if JSON parsing fails.
    end
  end

  def get_weather_forecast(forecast_url)
    # Developer Note: Fetches the actual forecast data from the weather.gov forecast URL.
    return nil unless forecast_url.present? && forecast_url.start_with?("http") # Basic URL validation.

    uri = URI(forecast_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)
    return nil if response.code != "200"

    begin
      data = JSON.parse(response.body)
      data["properties"]["periods"] # Returns array of forecast periods.
    rescue JSON::ParserError
      nil # Return nil if JSON parsing fails.
    end
  end

  def extract_weather_data(periods)
    # Developer Note: Extracts evening forecast data (lows) for the next 3 days and pairs with daytime highs.
    # "This Afternoon" and "Tonight" are treated as "Today" for user-friendly display.
    time_periods = periods.select { |p| p["isDaytime"] == false } # Focus on evening periods.
    time_periods.select { |p| within_3_days(p) }.map do |period|
      {
        name: [ "This Afternoon", "Tonight" ].include?(period["name"]) ? "Today" : period["name"],
        day: DateTime.parse(period["startTime"]).strftime("%D"),
        current_temp: period["temperature"], # Evening temperature (low).
        wind_speed: period["windSpeed"],
        wind_direction: period["windDirection"],
        wind_icon: period["icon"],
        high: high_for_day(period["startTime"], periods), # Fetch corresponding daytime high.
        low: period["temperature"],
        temp_unit: period["temperatureUnit"],
        description: period["shortForecast"]
      }
    end

    # Developer Note: This method assumes evening periods are the primary focus.
    # If no matching daytime period exists for a high, `high` will be nil.
  end

  def within_3_days(period)
    # Developer Note: Filters periods to include only those within the next 3 days.
    start_time = DateTime.parse(period["startTime"]).at_beginning_of_day
    start_time <= (DateTime.now + 3)
  end

  def high_for_day(start_time, periods)
    # Developer Note: Finds the daytime high for the same day as the evening period.
    (periods.detect do |period|
      period["isDaytime"] && # Check if it's daytime
      DateTime.parse(period["startTime"]).at_beginning_of_day == DateTime.parse(start_time).at_beginning_of_day
    end || {})["temperature"] # Returns nil if no matching daytime period found.
  end
end
