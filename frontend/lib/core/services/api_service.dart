// lib/core/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String get _resolvedBase {
  if (kIsWeb) {
    final uri = Uri.base;
    final port = uri.port;
    final portStr = (port == 0 || port == 80 || port == 443) ? '' : ':$port';
    return '${uri.scheme}://${uri.host}$portStr/api';
  }
  return const String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000/api');
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class ApiService {
  late final Dio _dio;
  final _store = const FlutterSecureStorage();

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _resolvedBase,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) async {
        final tok = await _store.read(key: 'access_token');
        if (tok != null) opts.headers['Authorization'] = 'Bearer $tok';
        handler.next(opts);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          final rt = await _store.read(key: 'refresh_token');
          if (rt != null) {
            try {
              final res = await _dio.post('/auth/refresh', data: {'refresh_token': rt});
              final newTok = res.data['access_token'];
              await _store.write(key: 'access_token', value: newTok);
              err.requestOptions.headers['Authorization'] = 'Bearer $newTok';
              return handler.resolve(await _dio.fetch(err.requestOptions));
            } catch (_) { await _store.deleteAll(); }
          }
        }
        handler.next(err);
      },
    ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? q}) => _dio.get(path, queryParameters: q);
  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? q}) => _dio.post(path, data: data, queryParameters: q);
  Future<Response> put(String path, {dynamic data}) => _dio.put(path, data: data);
  Future<Response> delete(String path, {dynamic data}) => _dio.delete(path, data: data);
  Future<Response> patch(String path, {dynamic data}) => _dio.patch(path, data: data);
  Future<Response> upload(String path, FormData fd, {void Function(int,int)? onProgress}) =>
    _dio.post(path, data: fd, options: Options(headers: {'Content-Type': 'multipart/form-data'}), onSendProgress: onProgress);

  Future<void> saveTokens(String access, String refresh) async {
    await _store.write(key: 'access_token',  value: access);
    await _store.write(key: 'refresh_token', value: refresh);
  }
  Future<String?> getToken()  => _store.read(key: 'access_token');
  Future<void>    clearTokens() => _store.deleteAll();
}
