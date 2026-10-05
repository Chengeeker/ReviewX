import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/navigation/x_deep_link.dart';

void main() {
  test('recognizes X and Twitter post, profile, and app destinations', () {
    final post = XLinkTarget.parse('https://x.com/alice/status/12345?s=20');
    expect(post?.kind, XLinkKind.post);
    expect(post?.postId, '12345');

    final legacyPost =
        XLinkTarget.parse('https://mobile.twitter.com/i/web/status/67890');
    expect(legacyPost?.kind, XLinkKind.post);
    expect(legacyPost?.postId, '67890');

    final profile = XLinkTarget.parse('https://www.twitter.com/alice');
    expect(profile?.kind, XLinkKind.profile);
    expect(profile?.handle, 'alice');

    expect(XLinkTarget.parse('https://x.com/explore')?.kind, XLinkKind.explore);
    expect(
        XLinkTarget.parse('https://x.com/search?q=flutter')?.query, 'flutter');
  });

  test('rejects non-X origins and malformed or credential-bearing URLs', () {
    expect(
        XLinkTarget.parse('https://x.com.evil.test/alice/status/123'), isNull);
    expect(XLinkTarget.parse('https://alice@x.com/alice/status/123'), isNull);
    expect(XLinkTarget.parse('https://x.com:8443/alice/status/123'), isNull);
    expect(XLinkTarget.parse('javascript:alert(1)'), isNull);
    expect(XLinkTarget.parse('https://x.com/alice/status/nope')?.kind,
        XLinkKind.other);
  });
}
