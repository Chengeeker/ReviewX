import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import 'timeline_page.dart';

class XProfileLinkPage extends ConsumerStatefulWidget {
  const XProfileLinkPage({super.key, required this.handle});
  final String handle;

  @override
  ConsumerState<XProfileLinkPage> createState() => _XProfileLinkPageState();
}

class _XProfileLinkPageState extends ConsumerState<XProfileLinkPage> {
  SocialUser? _user;
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final controller = ref.read(appControllerProvider),
        epoch = controller.epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await controller.adapter.userByHandle(widget.handle);
      if (!mounted || request != _request || epoch != controller.epoch) return;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (error) {
      controller.report(error);
      if (mounted && request == _request && epoch == controller.epoch) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user != null) {
      return ProfilePage(user: user, refreshOnOpen: false);
    }
    return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle}')),
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? '无法读取用户资料', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                        onPressed: _load, child: const Text('重试'))
                  ])));
  }
}
