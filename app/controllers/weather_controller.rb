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
    data = JSON.parse(response.body)

    return nil if response.code != "200"
    data["properties"]["forecast"]
  end

  def get_weather_forecast(forecast_url)
    uri = URI(forecast_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "weather-script (your-email@example.com)"

    response = http.request(request)
    data = JSON.parse(response.body)

    return nil if response.code != "200"
    data["properties"]["periods"]
  end

  def extract_weather_data(periods)
    # limit to 4 days, today + 3 days
    # if a period looks like this:
    # {
    #   "number": 3,
    #   "name": "Thursday",
    #   "startTime": "2025-04-10T06:00:00-05:00",
    #   "endTime": "2025-04-10T18:00:00-05:00",
    #   "isDaytime": true,
    #   "temperature": 68,
    #   "temperatureUnit": "F",
    #   "temperatureTrend": "",
    #   "probabilityOfPrecipitation": {
    #     "unitCode": "wmoUnit:percent",
    #     "value": null
    #   },
    #   "windSpeed": "10 to 25 mph",
    #   "windDirection": "NW",
    #   "icon": "https://api.weather.gov/icons/land/day/wind_few?size=medium",
    #   "shortForecast": "Sunny",
    #   "detailedForecast": "Sunny, with a high near 68. Northwest wind 10 to 25 mph, with gusts as high as 35 mph."
    # },
    # parse the startTime to get the date and use that date to get the next 3 days

    periods.select { |p| within_3_days(p) }.map do |period|
      {
        name: period["name"],
        day: DateTime.parse(period["startTime"]).strftime("%a"),
        current_temp: period["temperature"],
        temp_unit: period["temperatureUnit"],
        wind_speed: period["windSpeed"],
        wind_direction: period["windDirection"],
        wind_icon: period["icon"],
        high: period["temperature"],
        low: period["temperature"],
        description: period["shortForecast"]
      }
    end
  end

  def within_3_days(period)
    start_time = DateTime.parse(period["startTime"]).at_beginning_of_day
    start_time <= (DateTime.now + 3)
  end
end
