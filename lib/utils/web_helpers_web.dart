// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void replaceUrlState(String path) {
  try {
    html.window.history.replaceState(null, 'Email Client', path);
  } catch (e) {
    // Ignore or log
  }
}

void redirectTo(String url) {
  try {
    html.window.location.assign(url);
  } catch (e) {
    // Ignore or log
  }
}

void downloadFileWeb(String fileName, String contentType, String base64Data) {
  try {
    js.context.callMethod('eval', ["""
      var link = document.createElement('a');
      link.href = 'data:$contentType;base64,$base64Data';
      link.download = '$fileName';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    """]);
  } catch (e) {
    // Ignore or log
  }
}
