import 'package:web/web.dart' as web;

bool closeBrowserWindow() {
  web.window.close();
  return true;
}

bool replaceBrowserLocation(String url) {
  web.window.location.replace(url);
  return true;
}
