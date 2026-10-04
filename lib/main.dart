import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/image_cache_maintenance.dart';
import 'core/services/notification_poll.dart';
import 'core/services/network_routing.dart';
import 'core/storage/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/haptic_feedback_util.dart';
import 'presentation/home_page.dart';
import 'twitter/auth/app_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['ReviewX (MIT)'], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks(['Review components (MIT)'],
        await rootBundle.loadString('licenses/Review-MIT.txt'));
    yield LicenseEntryWithLineBreaks(['X transaction data and encoder (MIT)'],
        await rootBundle.loadString('licenses/fa0311-transaction-mit.txt'));
    yield LicenseEntryWithLineBreaks(['Source provenance'],
        await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
  });
  final storage = await StorageService.init();
  await NetworkRouting.initialize(storage, configurePlayer: true);
  runApp(ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const ReviewXApp()));
  unawaited(ImageCacheMaintenance.trimOnStartup());
  unawaited(NotificationPoll.sync().catchError((Object _) {}));
}

@pragma('vm:entry-point')
void notificationWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final items = await NotificationPoll.run();
    await NotificationPoll.channel.invokeMethod('pollComplete', items);
  } catch (_) {
    // No automatic rapid retry, no credentials/errors in notification text.
    await NotificationPoll.channel.invokeMethod('pollComplete', <dynamic>[]);
  }
}

class ReviewXApp extends ConsumerStatefulWidget {
  const ReviewXApp({super.key});
  @override
  ConsumerState<ReviewXApp> createState() => _ReviewXAppState();
}

class _ReviewXAppState extends ConsumerState<ReviewXApp> {
  @override
  void initState() {
    super.initState();
    ref.read(appControllerProvider).restore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider),
        controller = ref.watch(appControllerProvider);
    HapticFeedbackUtil.isEnabled = theme.enableHaptics;
    return DynamicColorBuilder(
        builder: (light, dark) => MaterialApp(
            title: 'ReviewX',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(
                dynamicColorScheme: theme.useDynamicColor ? light : null,
                colorIndex: theme.themeColorIndex,
                fontWeightAdjustment: theme.effectiveFontWeightAdjustment),
            darkTheme: AppTheme.darkTheme(
                dynamicColorScheme: theme.useDynamicColor ? dark : null,
                colorIndex: theme.themeColorIndex,
                isPureBlack: theme.isPureBlackDark,
                fontWeightAdjustment: theme.effectiveFontWeightAdjustment),
            themeMode: theme.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: !controller.ready
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()))
                : controller.startupError != null
                    ? Scaffold(
                        body: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                            Text(controller.startupError!),
                            TextButton(
                                onPressed: controller.restore,
                                child: const Text('重试')),
                            TextButton(
                                onPressed: controller.logout,
                                child: const Text('清除登录信息'))
                          ])))
                    : HomePage(key: ValueKey(controller.epoch))));
  }
}
