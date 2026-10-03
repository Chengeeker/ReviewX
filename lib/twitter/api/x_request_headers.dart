/// Public request headers used for X-hosted media.
///
/// CDN image loads use the X origin and browser user agent, but deliberately do
/// not include the signed-in account's Cookie or API authorization headers.
abstract final class XRequestHeaders {
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const media = <String, String>{
    'Referer': 'https://x.com/',
    'User-Agent': userAgent,
  };
}
