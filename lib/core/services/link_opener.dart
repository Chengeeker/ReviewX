import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keep web links in the app's browser surface without injecting auth headers.
Future<bool> openAppLink(BuildContext context, Uri uri) async {
  if (!const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('不支持的网页链接')));
    }
    return false;
  }
  try {
    if (await launchUrl(uri,
        mode: LaunchMode.inAppBrowserView,
        browserConfiguration: const BrowserConfiguration(showTitle: true))) {
      return true;
    }
  } catch (_) {
    // Offer an explicit external-browser action when the in-app surface fails.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('无法在应用内打开此网页'),
        action: SnackBarAction(
            label: '外部打开',
            onPressed: () async {
              try {
                if (await launchUrl(uri,
                    mode: LaunchMode.externalApplication)) {
                  return;
                }
              } catch (_) {}
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('未找到可用的浏览器')));
              }
            })));
  }
  return false;
}
