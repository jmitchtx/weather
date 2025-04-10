class WeatherController < ApplicationController
  def index
    @address = params[:address]
    @weather_data = nil
    @from_cache = false

    if @address.present?
      cache_key = "weather_#{Digest::MD5.hexdigest(@address)}"
      cached_data = Rails.cache.read(cache_key)

      if cached_data && params[:force].blank?
        @weather_data = cached_data
        @from_cache = true
      else
        coordinates = geocode_address(@address)
        if coordinates
          forecast_url = get_forecast_url(coordinates[:lat], coordinates[:lon])
          Rails.logger.info("Forecast URL: #{forecast_url}")
          if forecast_url
            periods = get_weather_forecast(forecast_url)

            if periods
              @weather_data = extract_weather_data(periods)
              Rails.cache.write(cache_key, @weather_data, expires_in: 30.minutes)
            end
          end
        end
      end
    end
  end

  private

  def geocode_address(address)
    encoded_address = URI.encode_www_form_component(address)
    url = "https://nominatim.openstreetmap.org/search?q=#{encoded_address}&format=json&limit=1"

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)
    data = JSON.parse(response.body)

    Rails.logger.info("Geocode response: #{data.inspect}")
    return nil if data.empty?

    Rails.logger.info("Geocode coordinates: #{data[0]['lat'].to_f}, #{data[0]['lon'].to_f}")
    { lat: data[0]["lat"].to_f.round(2), lon: data[0]["lon"].to_f.round(2) }
  end

  def get_forecast_url(lat, lon)
    url = "https://api.weather.gov/points/#{lat},#{lon}"
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)

    return nil if response.code != "200"

    begin
      data = JSON.parse(response.body)
      data["properties"]["forecast"]
    rescue JSON::ParserError
      nil
    end
  end

  def get_weather_forecast(forecast_url)
    return nil unless forecast_url.present? && forecast_url.start_with?("http")

    uri = URI(forecast_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)
    return nil if response.code != "200"

    begin
      data = JSON.parse(response.body)
      data["properties"]["periods"]
    rescue JSON::ParserError
      nil
    end
  end

  def extract_weather_data(periods)
    time_periods = periods.select { |p| p["isDaytime"] == false }
    time_periods.select { |p| within_3_days(p) }.map do |period|
      {
        name: [ "This Afternoon", "Tonight" ].include?(period["name"]) ? "Today" : period["name"],
        day: DateTime.parse(period["startTime"]).strftime("%D"),
        current_temp: period["temperature"],
        wind_speed: period["windSpeed"],
        wind_direction: period["windDirection"],
        wind_icon: period["icon"],
        high: high_for_day(period["startTime"], periods),
        low: period["temperature"],
        temp_unit: period["temperatureUnit"],
        description: period["shortForecast"]
      }
    end
  end

  def within_3_days(period)
    start_time = DateTime.parse(period["startTime"]).at_beginning_of_day
    start_time <= (DateTime.now + 3)
  end

  def high_for_day(start_time, periods)
    (periods.detect do |period|
      period["isDaytime"] &&  # Check if it's daytime
      DateTime.parse(period["startTime"]).at_beginning_of_day == DateTime.parse(start_time).at_beginning_of_day
    end || {})["temperature"]
  end
end
