import 'package:web/web.dart' as web;

void updateSiteMetadata(String title, String iconUrl) {
  final siteTitle = title.trim().isEmpty ? 'Abdullah Portfolio' : title.trim();
  web.document.title = siteTitle;

  final appName = web.document.querySelector(
    'meta[name="application-name"]',
  ) as web.HTMLMetaElement?;
  if (appName != null) appName.content = siteTitle;

  final favicon = web.document.querySelector(
    '#portfolio-favicon',
  ) as web.HTMLLinkElement?;
  if (favicon != null) {
    favicon.href = iconUrl.trim().isEmpty ? 'favicon.png' : iconUrl.trim();
  }
}
