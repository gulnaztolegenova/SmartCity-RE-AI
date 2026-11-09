import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

class CloudRunApiException implements Exception {
  CloudRunApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CloudRunApiException($statusCode): $message';
}

class CloudRunApi {
  CloudRunApi({
    http.Client? client,
    String? baseUrl,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       baseUrl = baseUrl ?? AppConstants.apiBaseUrl,
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final String baseUrl;
  final DateTime Function() _clock;
  final _responses = <String, _CachedApiResponse>{};
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  int _cacheGeneration = 0;

  /// Shared by all pages, scoped to the signed-in user's API instance.
  /// No result survives the next quarter-hour or more than three minutes.
  void clearCache() {
    _cacheGeneration++;
    _responses.clear();
  }

  Future<Map<String, dynamic>> _remember(
    String key,
    Future<Map<String, dynamic>> Function() request, {
    bool forceRefresh = false,
  }) {
    final now = _clock();
    _responses.removeWhere((_, entry) => !now.isBefore(entry.expiresAt));
    final cached = _responses[key];
    if (!forceRefresh && cached != null) return Future.value(cached.data);
    final pending = _pending[key];
    if (pending != null) return pending;
    _responses.remove(key);
    final generation = _cacheGeneration;
    late final Future<Map<String, dynamic>> future;
    future = _withSlot(request)
        .then((data) {
          if (generation == _cacheGeneration) {
            final completed = _clock();
            final nextQuarter = DateTime.fromMillisecondsSinceEpoch(
              ((completed.millisecondsSinceEpoch ~/ 900000) + 1) * 900000,
            );
            final ttl = completed.add(const Duration(minutes: 3));
            if (_responses.length >= 24) {
              _responses.remove(_responses.keys.first);
            }
            _responses[key] = _CachedApiResponse(
              data,
              ttl.isBefore(nextQuarter) ? ttl : nextQuarter,
            );
          }
          return data;
        })
        .whenComplete(() {
          if (identical(_pending[key], future)) _pending.remove(key);
        });
    _pending[key] = future;
    return future;
  }

  Future<Map<String, dynamic>> _withSlot(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    // Match the server's two request slots rather than opening five cold
    // instances when the dashboard and metadata load together.
    if (_active >= 2) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await request();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  Future<Map<String, dynamic>> getHealth({
    Duration timeout = const Duration(seconds: 10),
    int retries = 1,
  }) => _getJson('/health', timeout: timeout, retries: retries);

  Future<Map<String, dynamic>> fetchMeta({
    Duration timeout = const Duration(seconds: 10),
    int retries = 1,
  }) => _getJson('/meta', timeout: timeout, retries: retries);

  Future<Map<String, dynamic>> fetchForecast({
    required double lat,
    required double lon,
    required int days,
    int stepMinutes = 15,
    String timezone = AppConstants.defaultTimezone,
    bool inverseY = true,
    double? capacityKw,
    double? tiltDeg,
    double? azimuthDeg,
    double? windCapacityKw,
    double? windHubHeightM,
    Duration timeout = const Duration(seconds: 15),
    int retries = 1,
    bool forceRefresh = false,
  }) {
    final query = <String, String>{
      'lat': lat.toString(),
      'lon': lon.toString(),
      'step_minutes': stepMinutes.toString(),
      'timezone': timezone,
      'inverse_y': inverseY.toString(),
    };
    if (capacityKw != null && capacityKw > 0) {
      query['capacity_kw'] = capacityKw.toString();
    }
    if (tiltDeg != null) {
      query['tilt_deg'] = tiltDeg.toString();
    }
    if (azimuthDeg != null) {
      query['azimuth_deg'] = azimuthDeg.toString();
    }
    if (windCapacityKw != null && windCapacityKw > 0) {
      query['wind_capacity_kw'] = windCapacityKw.toString();
    }
    if (windHubHeightM != null && windHubHeightM > 0) {
      query['wind_hub_height_m'] = windHubHeightM.toString();
    }

    return _getJson(
      '/forecast/${days}d',
      queryParameters: query,
      timeout: timeout,
      retries: retries,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> fetchMeteo({
    required double lat,
    required double lon,
    int hours = 48,
    int stepMinutes = 60,
    String timezone = AppConstants.defaultTimezone,
    Duration timeout = const Duration(seconds: 15),
    int retries = 1,
    bool forceRefresh = false,
  }) {
    return _getJson(
      '/meteo',
      queryParameters: <String, String>{
        'lat': lat.toString(),
        'lon': lon.toString(),
        'hours': hours.toString(),
        'step_minutes': stepMinutes.toString(),
        'timezone': timezone,
      },
      timeout: timeout,
      retries: retries,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> fetchLoadMeta({
    Duration timeout = const Duration(seconds: 15),
    int retries = 1,
  }) => _getJson('/load/meta', timeout: timeout, retries: retries);

  Future<Map<String, dynamic>> fetchLoadForecast({
    required int days,
    String? deviceId,
    double? scaleFactor,
    double? capacityKw,
    Duration timeout = const Duration(seconds: 15),
    int retries = 1,
    bool forceRefresh = false,
  }) {
    final query = <String, String>{};
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      query['device_id'] = deviceId.trim();
    }
    if (scaleFactor != null && scaleFactor > 0) {
      query['scale_factor'] = scaleFactor.toString();
    }
    if (capacityKw != null && capacityKw > 0) {
      query['capacity_kw'] = capacityKw.toString();
    }
    return _getJson(
      '/load/forecast/${days}d',
      queryParameters: query,
      timeout: timeout,
      retries: retries,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> fetchEnergyBalance({
    required double lat,
    required double lon,
    required int days,
    String timezone = AppConstants.defaultTimezone,
    int stepMinutes = 15,
    String? deviceId,
    double? scaleFactor,
    double? capacityKw,
    double? tiltDeg,
    double? azimuthDeg,
    double? windCapacityKw,
    double? windHubHeightM,
    Duration timeout = const Duration(seconds: 20),
    int retries = 1,
    bool forceRefresh = false,
  }) {
    final query = <String, String>{
      'lat': lat.toString(),
      'lon': lon.toString(),
      'days': days.toString(),
      'timezone': timezone,
      'step_minutes': stepMinutes.toString(),
    };
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      query['device_id'] = deviceId.trim();
    }
    if (scaleFactor != null && scaleFactor > 0) {
      query['scale_factor'] = scaleFactor.toString();
    }
    if (capacityKw != null && capacityKw > 0) {
      query['capacity_kw'] = capacityKw.toString();
    }
    if (tiltDeg != null) {
      query['tilt_deg'] = tiltDeg.toString();
    }
    if (azimuthDeg != null) {
      query['azimuth_deg'] = azimuthDeg.toString();
    }
    if (windCapacityKw != null && windCapacityKw > 0) {
      query['wind_capacity_kw'] = windCapacityKw.toString();
    }
    if (windHubHeightM != null && windHubHeightM > 0) {
      query['wind_hub_height_m'] = windHubHeightM.toString();
    }
    return _getJson(
      '/energy/balance',
      queryParameters: query,
      timeout: timeout,
      retries: retries,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> optimize({
    required double lat,
    required double lon,
    required int days,
    required Map<String, dynamic> battery,
    String timezone = AppConstants.defaultTimezone,
    String? deviceId,
    double? scaleFactor,
    double? capacityKw,
    double? tiltDeg,
    double? azimuthDeg,
    double? windCapacityKw,
    double? windHubHeightM,
    int dispatchStepMinutes = 60,
    int balanceStepMinutes = 15,
    List<String>? timestamps,
    List<double>? pvKwPred,
    List<double>? loadKwPred,
    Duration timeout = const Duration(seconds: 45),
    bool forceRefresh = false,
  }) {
    return _postJson(
      '/optimize',
      body: <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'days': days,
        'timezone': timezone,
        if (deviceId case final deviceId? when deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim(),
        if (scaleFactor != null && scaleFactor > 0) 'scale_factor': scaleFactor,
        if (capacityKw != null && capacityKw > 0) 'capacity_kw': capacityKw,
        ...?switch (tiltDeg) {
          final value? => <String, dynamic>{'tilt_deg': value},
          null => null,
        },
        ...?switch (azimuthDeg) {
          final value? => <String, dynamic>{'azimuth_deg': value},
          null => null,
        },
        if (windCapacityKw != null && windCapacityKw > 0)
          'wind_capacity_kw': windCapacityKw,
        if (windHubHeightM != null && windHubHeightM > 0)
          'wind_hub_height_m': windHubHeightM,
        'dispatch_step_minutes': dispatchStepMinutes,
        'balance_step_minutes': balanceStepMinutes,
        ...?switch (timestamps) {
          final value? => <String, dynamic>{'timestamps': value},
          null => null,
        },
        ...?switch (pvKwPred) {
          final value? => <String, dynamic>{'pv_kw_pred': value},
          null => null,
        },
        ...?switch (loadKwPred) {
          final value? => <String, dynamic>{'load_kw_pred': value},
          null => null,
        },
        'battery': battery,
      },
      timeout: timeout,
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? queryParameters,
    Duration timeout = const Duration(seconds: 30),
    int retries = 0,
    bool forceRefresh = false,
  }) {
    _ensureBaseUrlConfigured();
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: queryParameters);
    return _remember(
      'GET $uri',
      () => _sendGetJson(uri, timeout: timeout, retries: retries),
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> _sendGetJson(
    Uri uri, {
    required Duration timeout,
    required int retries,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final error = CloudRunApiException(
            response.body.isEmpty
                ? 'HTTP ${response.statusCode}'
                : response.body,
            statusCode: response.statusCode,
          );
          if (_shouldRetryStatus(response.statusCode) && attempt < retries) {
            await Future<void>.delayed(_retryDelay(attempt));
            continue;
          }
          throw error;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw CloudRunApiException('Invalid JSON payload.');
        }
        return decoded;
      } on TimeoutException catch (error, stackTrace) {
        lastError = CloudRunApiException('Request timed out: $uri');
        lastStackTrace = stackTrace;
        if (attempt >= retries) {
          Error.throwWithStackTrace(lastError, lastStackTrace);
        }
        await Future<void>.delayed(_retryDelay(attempt));
      } on http.ClientException catch (error, stackTrace) {
        lastError = CloudRunApiException(error.message);
        lastStackTrace = stackTrace;
        if (attempt >= retries) {
          Error.throwWithStackTrace(lastError, lastStackTrace);
        }
        await Future<void>.delayed(_retryDelay(attempt));
      } on CloudRunApiException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt >= retries || !_shouldRetryStatus(error.statusCode)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw CloudRunApiException('Unexpected Cloud Run request failure.');
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
    bool forceRefresh = false,
  }) {
    _ensureBaseUrlConfigured();
    final uri = Uri.parse('$baseUrl$path');
    final encoded = jsonEncode(body);
    return _remember(
      'POST $uri $encoded',
      () => _sendPostJson(uri, encoded, timeout),
      forceRefresh: forceRefresh,
    );
  }

  Future<Map<String, dynamic>> _sendPostJson(
    Uri uri,
    String encoded,
    Duration timeout,
  ) async {
    final response = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: encoded,
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudRunApiException(
        response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body,
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw CloudRunApiException('Invalid JSON payload.');
    }
    return decoded;
  }

  void _ensureBaseUrlConfigured() {
    if (baseUrl.trim().isEmpty) {
      throw CloudRunApiException('Cloud Run base URL is not configured.');
    }
  }

  static bool _shouldRetryStatus(int? statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  static Duration _retryDelay(int attempt) {
    return Duration(milliseconds: 350 * (attempt + 1));
  }

  void close() {
    clearCache();
    _client.close();
  }
}

class _CachedApiResponse {
  const _CachedApiResponse(this.data, this.expiresAt);
  final Map<String, dynamic> data;
  final DateTime expiresAt;
}
