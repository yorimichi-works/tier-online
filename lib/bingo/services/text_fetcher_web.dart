import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fetches a CORS-enabled URL as text from the browser (as oshireco does for
/// the iTunes Search API, which allows any origin).
Future<String> fetchText(Uri url) async {
  final response = await web.window.fetch(url.toString().toJS).toDart;
  if (!response.ok) throw StateError('HTTP ${response.status}');
  return (await response.text().toDart).toDart;
}
