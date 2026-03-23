
import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext ctx)  => MediaQuery.of(ctx).size.width < 600;
  static bool isTablet(BuildContext ctx)  => MediaQuery.of(ctx).size.width >= 600 && MediaQuery.of(ctx).size.width < 900;
  static bool isDesktop(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 900;
  static bool isWide(BuildContext ctx)    => MediaQuery.of(ctx).size.width >= 768;

  static double sidebarWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 1200) return 280;
    if (w >= 900)  return 240;
    if (w >= 600)  return 72;
    return 0;
  }

  static T adaptive<T>(BuildContext ctx, {required T mobile, T? tablet, required T desktop}) {
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx))  return tablet ?? desktop;
    return mobile;
  }

  static int gridCrossAxisCount(BuildContext ctx, {int mobile = 2, int tablet = 3, int desktop = 4}) {
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx))  return tablet;
    return mobile;
  }

  static double maxContentWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w > 1400) return 1200;
    if (w > 1000) return 900;
    return w;
  }

  static EdgeInsets pagePadding(BuildContext ctx) {
    if (isDesktop(ctx)) return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    if (isTablet(ctx))  return const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    return const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  }
}
