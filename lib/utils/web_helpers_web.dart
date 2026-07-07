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

void openInNewTab(String url) {
  try {
    html.AnchorElement anchor = html.AnchorElement(href: url)
      ..target = '_blank'
      ..rel = 'noopener noreferrer';
    anchor.click();
  } catch (e) {
    try {
      html.window.open(url, '_blank');
    } catch (e2) {
      // Ignore or log
    }
  }
}

void printWindowWeb() {
  try {
    html.window.print();
  } catch (e) {
    // Ignore or log
  }
}

void printHtmlWeb(String title, String htmlBody) {
  try {
    String safeTitle = title.replaceAll("'", "\\'").replaceAll('\n', ' ').replaceAll('\r', '');
    String safeHtml = htmlBody.replaceAll("'", "\\'").replaceAll('\n', ' ').replaceAll('\r', '');
    final jsCode = """
      var iframe = document.createElement('iframe');
      iframe.style.position = 'absolute';
      iframe.style.width = '0px';
      iframe.style.height = '0px';
      iframe.style.border = 'none';
      document.body.appendChild(iframe);
      
      var doc = iframe.contentWindow.document;
      doc.open();
      doc.write('<html><head><title>' + '$safeTitle' + '</title></head><body style="font-family: sans-serif; padding: 20px;">' + '$safeHtml' + '</body></html>');
      doc.close();
      
      iframe.contentWindow.focus();
      setTimeout(function() {
        iframe.contentWindow.print();
        document.body.removeChild(iframe);
      }, 500);
    """;
    js.context.callMethod('eval', [jsCode]);
  } catch (e) {
    // Ignore or log
  }
}
