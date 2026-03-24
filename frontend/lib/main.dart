import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/notification_provider.dart';
import 'core/services/socket_service.dart';
import 'core/services/push_service.dart';
import 'features/overlay/app_overlay.dart';

const _stripeKey = String.fromEnvironment(
  'STRIPE_PUBLISHABLE_KEY',
  defaultValue: 'pk_test_placeholder',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // Initialize Stripe (safe on both web and native)
  try {
    Stripe.publishableKey = _stripeKey;
    if (!kIsWeb) {
      Stripe.merchantIdentifier = 'com.redorrange.app';
      Stripe.urlScheme = 'redorrange';
    }
    await Stripe.instance.applySettings();
  } catch (_) {}

  // Local push notifications (no-op on web, uses browser Notification API)
  await PushService.init();

  runApp(const ProviderScope(child: RedOrrangeApp()));
}

class RedOrrangeApp extends ConsumerStatefulWidget {
  const RedOrrangeApp({super.key});
  @override ConsumerState<RedOrrangeApp> createState() => _S();
}

class _S extends ConsumerState<RedOrrangeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider).whenData((user) {
        if (user != null) {
          final socket = ref.read(socketServiceProvider);
          socket.connect();
          PushService.attachToSocket(socket);
          ref.read(notificationProviderInstance.notifier).refresh();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router    = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'RedOrrange',
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.light,
      darkTheme:  AppTheme.dark,
      themeMode:  themeMode,
      routerConfig: router,
      builder: (ctx, child) =>
          child == null ? const SizedBox.shrink() : AppOverlay(child: child),
    );
  }
}
