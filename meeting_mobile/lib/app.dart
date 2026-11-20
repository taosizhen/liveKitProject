import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';

/// 应用根组件
class MeetingApp extends ConsumerWidget {
  const MeetingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '会议协助平台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0.5,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
