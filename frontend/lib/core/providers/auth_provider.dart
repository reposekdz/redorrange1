import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../models/models.dart';

final authControllerProvider = Provider<AuthController>((ref) => AuthController(ref));
final authStateProvider = FutureProvider<UserModel?>((ref) async {
  final api = ref.watch(apiServiceProvider);
  try {
    final r = await api.get('/users/me');
    if (r.data['success'] == true && r.data['user'] != null) {
      final u = UserModel.fromJson(Map<String, dynamic>.from(r.data['user']));
      ref.read(socketServiceProvider).connect();
      return u;
    }
    return null;
  } catch (_) { return null; }
});
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).value;
});

class AuthController {
  final Ref _ref;
  AuthController(this._ref);

  Future<Map<String,dynamic>> sendOtp(String phone, String cc) async {
    final r = await _ref.read(apiServiceProvider).post('/auth/send-otp', data: {'phone_number': phone, 'country_code': cc});
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> verifyOtp(String phone, String cc, String code) async {
    final r = await _ref.read(apiServiceProvider).post('/auth/verify-otp', data: {'phone_number': phone, 'country_code': cc, 'code': code});
    final d = Map<String,dynamic>.from(r.data);
    if (d['success'] == true) {
      await _ref.read(apiServiceProvider).saveTokens(d['access_token'] ?? '', d['refresh_token'] ?? '');
      _ref.read(socketServiceProvider).connect();
      _ref.refresh(authStateProvider);
    }
    return d;
  }

  Future<Map<String,dynamic>> generateQR() async {
    final r = await _ref.read(apiServiceProvider).get('/auth/qr-generate');
    return Map<String,dynamic>.from(r.data);
  }

  Future<Map<String,dynamic>> checkQRStatus(String sessionId) async {
    final r = await _ref.read(apiServiceProvider).get('/auth/qr-status/$sessionId');
    final d = Map<String,dynamic>.from(r.data);
    if (d['status'] == 'confirmed' && d['access_token'] != null) {
      await _ref.read(apiServiceProvider).saveTokens(d['access_token'], d['refresh_token'] ?? '');
      _ref.read(socketServiceProvider).connect();
      _ref.refresh(authStateProvider);
    }
    return d;
  }

  Future<void> refreshUser() async => _ref.refresh(authStateProvider);

  Future<void> logout() async {
    try { await _ref.read(apiServiceProvider).post('/auth/logout'); } catch (_) {}
    await _ref.read(apiServiceProvider).clearTokens();
    _ref.read(socketServiceProvider).disconnect();
    _ref.refresh(authStateProvider);
  }
}
