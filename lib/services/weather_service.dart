import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result from current weather API
class WeatherResult {
  final bool success;
  final String? location;
  final String? description;
  final double? temperature;
  final double? feelsLike;
  final int? humidity;
  final double? windSpeed;
  final String? error;

  WeatherResult({
    required this.success,
    this.location,
    this.description,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.windSpeed,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    if (location != null) 'location': location,
    if (description != null) 'description': description,
    if (temperature != null) 'temperature_fahrenheit': temperature,
    if (feelsLike != null) 'feels_like_fahrenheit': feelsLike,
    if (humidity != null) 'humidity_percent': humidity,
    if (windSpeed != null) 'wind_speed_mph': windSpeed,
    if (error != null) 'error': error,
  };

  String toSummary() {
    if (!success) return error ?? 'Unable to get weather';
    return '$location: ${temperature?.round()} degrees, $description. '
           'Feels like ${feelsLike?.round()} degrees. '
           'Humidity $humidity%, wind ${windSpeed?.round()} mph.';
  }
}

/// Single forecast entry
class ForecastEntry {
  final DateTime dateTime;
  final String description;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final double? rainChance; // probability of precipitation

  ForecastEntry({
    required this.dateTime,
    required this.description,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    this.rainChance,
  });
}

/// Result from forecast API
class ForecastResult {
  final bool success;
  final String? location;
  final List<ForecastEntry>? forecasts;
  final String? error;

  ForecastResult({
    required this.success,
    this.location,
    this.forecasts,
    this.error,
  });

  /// Get a summary for the next few periods
  String toSummary({int periods = 4}) {
    if (!success) return error ?? 'Unable to get forecast';
    if (forecasts == null || forecasts!.isEmpty) return 'No forecast data available';

    final buffer = StringBuffer('$location forecast: ');
    final entries = forecasts!.take(periods);

    for (final entry in entries) {
      final time = _formatTime(entry.dateTime);
      buffer.write('$time: ${entry.temperature.round()} degrees, ${entry.description}. ');
    }

    return buffer.toString();
  }

  /// Get tomorrow's forecast summary
  String tomorrowSummary() {
    if (!success) return error ?? 'Unable to get forecast';
    if (forecasts == null || forecasts!.isEmpty) return 'No forecast data available';

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // Find forecasts for tomorrow
    final tomorrowForecasts = forecasts!.where((f) {
      final date = DateTime(f.dateTime.year, f.dateTime.month, f.dateTime.day);
      return date.isAtSameMomentAs(tomorrow);
    }).toList();

    if (tomorrowForecasts.isEmpty) return 'No forecast available for tomorrow';

    // Get morning, afternoon, evening
    ForecastEntry? morning, afternoon, evening;
    for (final f in tomorrowForecasts) {
      final hour = f.dateTime.hour;
      if (hour >= 6 && hour < 12) morning = f;
      if (hour >= 12 && hour < 18) afternoon = f;
      if (hour >= 18 && hour < 22) evening = f;
    }

    final buffer = StringBuffer('Tomorrow in $location: ');
    if (morning != null) buffer.write('Morning ${morning.temperature.round()} degrees ${morning.description}. ');
    if (afternoon != null) buffer.write('Afternoon ${afternoon.temperature.round()} degrees ${afternoon.description}. ');
    if (evening != null) buffer.write('Evening ${evening.temperature.round()} degrees ${evening.description}.');

    return buffer.toString();
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour$period';
  }
}

/// Air quality result
class AirQualityResult {
  final bool success;
  final String? location;
  final int? aqi; // Air Quality Index 1-5
  final String? qualityLevel; // Good, Fair, Moderate, Poor, Very Poor
  final double? pm25;
  final double? pm10;
  final double? co;
  final double? no2;
  final double? o3;
  final String? error;

  AirQualityResult({
    required this.success,
    this.location,
    this.aqi,
    this.qualityLevel,
    this.pm25,
    this.pm10,
    this.co,
    this.no2,
    this.o3,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    if (location != null) 'location': location,
    if (aqi != null) 'aqi': aqi,
    if (qualityLevel != null) 'quality_level': qualityLevel,
    if (pm25 != null) 'pm2_5': pm25,
    if (pm10 != null) 'pm10': pm10,
    if (error != null) 'error': error,
  };

  String toSummary() {
    if (!success) return error ?? 'Unable to get air quality';
    return '$location air quality: $qualityLevel (AQI $aqi). PM2.5: ${pm25?.toStringAsFixed(1)} µg/m³.';
  }

  static String aqiToLevel(int aqi) {
    switch (aqi) {
      case 1: return 'Good';
      case 2: return 'Fair';
      case 3: return 'Moderate';
      case 4: return 'Poor';
      case 5: return 'Very Poor';
      default: return 'Unknown';
    }
  }
}

/// Service for fetching weather data from OpenWeather API
class WeatherService {
  final String _apiKey;
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const String _geoUrl = 'https://api.openweathermap.org/geo/1.0';

  WeatherService(this._apiKey);

  /// Get coordinates for a location (needed for air quality API)
  Future<Map<String, double>?> _getCoordinates(String location) async {
    try {
      final uri = Uri.parse('$_geoUrl/direct').replace(queryParameters: {
        'q': location,
        'limit': '1',
        'appid': _apiKey,
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          return {
            'lat': (data[0]['lat'] as num).toDouble(),
            'lon': (data[0]['lon'] as num).toDouble(),
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current weather for a location
  Future<WeatherResult> getWeather(String location) async {
    try {
      final uri = Uri.parse('$_baseUrl/weather').replace(queryParameters: {
        'q': location,
        'appid': _apiKey,
        'units': 'imperial',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return WeatherResult(
          success: true,
          location: '${data['name']}, ${data['sys']['country']}',
          description: data['weather'][0]['description'],
          temperature: (data['main']['temp'] as num).toDouble(),
          feelsLike: (data['main']['feels_like'] as num).toDouble(),
          humidity: data['main']['humidity'] as int,
          windSpeed: (data['wind']['speed'] as num).toDouble(),
        );
      } else if (response.statusCode == 404) {
        return WeatherResult(
          success: false,
          error: 'Location "$location" not found. Try a different city name.',
        );
      } else {
        return WeatherResult(
          success: false,
          error: 'Weather service error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return WeatherResult(
        success: false,
        error: 'Failed to fetch weather: $e',
      );
    }
  }

  /// Get 5-day / 3-hour forecast for a location
  Future<ForecastResult> getForecast(String location) async {
    try {
      final uri = Uri.parse('$_baseUrl/forecast').replace(queryParameters: {
        'q': location,
        'appid': _apiKey,
        'units': 'imperial',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List forecastList = data['list'];

        final forecasts = forecastList.map<ForecastEntry>((item) {
          return ForecastEntry(
            dateTime: DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000),
            description: item['weather'][0]['description'],
            temperature: (item['main']['temp'] as num).toDouble(),
            feelsLike: (item['main']['feels_like'] as num).toDouble(),
            humidity: item['main']['humidity'] as int,
            windSpeed: (item['wind']['speed'] as num).toDouble(),
            rainChance: item['pop'] != null ? (item['pop'] as num).toDouble() * 100 : null,
          );
        }).toList();

        return ForecastResult(
          success: true,
          location: '${data['city']['name']}, ${data['city']['country']}',
          forecasts: forecasts,
        );
      } else if (response.statusCode == 404) {
        return ForecastResult(
          success: false,
          error: 'Location "$location" not found.',
        );
      } else {
        return ForecastResult(
          success: false,
          error: 'Forecast service error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return ForecastResult(
        success: false,
        error: 'Failed to fetch forecast: $e',
      );
    }
  }

  /// Get air quality for a location
  Future<AirQualityResult> getAirQuality(String location) async {
    try {
      // First get coordinates
      final coords = await _getCoordinates(location);
      if (coords == null) {
        return AirQualityResult(
          success: false,
          error: 'Could not find coordinates for "$location".',
        );
      }

      final uri = Uri.parse('$_baseUrl/air_pollution').replace(queryParameters: {
        'lat': coords['lat'].toString(),
        'lon': coords['lon'].toString(),
        'appid': _apiKey,
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final item = data['list'][0];
        final aqi = item['main']['aqi'] as int;
        final components = item['components'];

        return AirQualityResult(
          success: true,
          location: location,
          aqi: aqi,
          qualityLevel: AirQualityResult.aqiToLevel(aqi),
          pm25: (components['pm2_5'] as num?)?.toDouble(),
          pm10: (components['pm10'] as num?)?.toDouble(),
          co: (components['co'] as num?)?.toDouble(),
          no2: (components['no2'] as num?)?.toDouble(),
          o3: (components['o3'] as num?)?.toDouble(),
        );
      } else {
        return AirQualityResult(
          success: false,
          error: 'Air quality service error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return AirQualityResult(
        success: false,
        error: 'Failed to fetch air quality: $e',
      );
    }
  }
}
