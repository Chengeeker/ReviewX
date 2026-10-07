import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

AppBar buildFrostedAppBar(
  BuildContext context, {
  Widget? leading,
  required Widget? title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
  double? toolbarHeight,
}) {
  final theme = Theme.of(context);
  final baseColor =
      theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor;
  return AppBar(
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    title: title,
    actions: actions,
    bottom: bottom,
    toolbarHeight: toolbarHeight,
    backgroundColor: baseColor.withValues(alpha: 0.45),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    flexibleSpace: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor.withValues(alpha: 0.95),
                baseColor.withValues(alpha: 0.0),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
                width: 0.5,
              ),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}
