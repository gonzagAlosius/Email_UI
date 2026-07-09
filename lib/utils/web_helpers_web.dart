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

void openEmailInNewWindow({
  required String subject,
  required String senderName,
  required String senderEmail,
  required String toEmail,
  required String dateStr,
  required String content,
}) {
  try {
    final String trimmed = content.trim();
    final bool isHtml =
        trimmed.contains('<html') ||
        trimmed.contains('<body') ||
        trimmed.contains('<div') ||
        trimmed.contains('<p') ||
        trimmed.contains('<table') ||
        trimmed.contains('<br') ||
        trimmed.contains('</');

    String processedBody;
    if (isHtml) {
      // Remove script tags to avoid XSS in same-origin window
      processedBody = trimmed.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', caseSensitive: false), '');
    } else {
      final escaped = trimmed
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
      processedBody = '<div style="white-space: pre-wrap; font-family: sans-serif; font-size: 14px; color: #334155;">$escaped</div>';
    }

    String escSubject = subject
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    String escSenderName = senderName
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    String escSenderEmail = senderEmail
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    String escToEmail = toEmail
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    String escDateStr = dateStr
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

    String avatarChar = senderName.trim().isNotEmpty
        ? senderName.trim().substring(0, 1).toUpperCase()
        : 'U';

    final String pageHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$escSubject</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #1e293b;
      background-color: #f8fafc;
      margin: 0;
      padding: 0;
      line-height: 1.5;
    }
    .container {
      max-width: 800px;
      margin: 40px auto;
      background-color: #ffffff;
      border: 1px solid #e2e8f0;
      border-radius: 16px;
      box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
      overflow: hidden;
    }
    .action-bar {
      display: flex;
      justify-content: flex-end;
      align-items: center;
      gap: 12px;
      padding: 12px 24px;
      background-color: #f1f5f9;
      border-bottom: 1px solid #e2e8f0;
    }
    @media print {
      .action-bar {
        display: none !important;
      }
      body {
        background-color: #ffffff !important;
      }
      .container {
        border: none !important;
        box-shadow: none !important;
        margin: 0 !important;
        max-width: 100% !important;
      }
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 8px 16px;
      font-size: 14px;
      font-weight: 500;
      border-radius: 8px;
      border: 1px solid #cbd5e1;
      background-color: #ffffff;
      color: #334155;
      cursor: pointer;
      transition: all 0.2s;
      text-decoration: none;
    }
    .btn:hover {
      background-color: #f8fafc;
      border-color: #94a3b8;
      color: #0f172a;
    }
    .btn-primary {
      background-color: #2563eb;
      color: #ffffff;
      border-color: #2563eb;
    }
    .btn-primary:hover {
      background-color: #1d4ed8;
      border-color: #1d4ed8;
      color: #ffffff;
    }
    .email-header {
      padding: 24px 32px;
      border-bottom: 1px solid #f1f5f9;
    }
    .subject {
      font-size: 24px;
      font-weight: 700;
      color: #0f172a;
      margin: 0 0 16px 0;
      line-height: 1.3;
    }
    .meta-row {
      display: flex;
      align-items: center;
      gap: 16px;
    }
    .avatar {
      width: 44px;
      height: 44px;
      border-radius: 50%;
      background-color: #dbeafe;
      color: #1e40af;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      font-weight: 700;
      text-transform: uppercase;
    }
    .meta-details {
      flex: 1;
      min-width: 0;
    }
    .sender-info {
      font-weight: 600;
      font-size: 15px;
      color: #0f172a;
      margin-bottom: 2px;
    }
    .sender-email {
      font-weight: 400;
      color: #64748b;
      font-size: 14px;
    }
    .recipient-info {
      font-size: 13px;
      color: #64748b;
    }
    .date-info {
      font-size: 13px;
      color: #94a3b8;
      white-space: nowrap;
    }
    .email-body {
      padding: 32px;
      font-size: 15px;
      line-height: 1.6;
      color: #334155;
    }
    /* Style tables inside body */
    .email-body table {
      border-collapse: collapse;
      width: 100%;
      margin: 16px 0;
    }
    .email-body th, .email-body td {
      border: 1px solid #cbd5e1;
      padding: 10px 12px;
      text-align: left;
    }
    .email-body th {
      background-color: #f1f5f9;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="action-bar">
      <button class="btn" onclick="window.print()">Print Email</button>
      <button class="btn btn-primary" onclick="window.close()">Close Window</button>
    </div>
    <div class="email-header">
      <h1 class="subject">$escSubject</h1>
      <div class="meta-row">
        <div class="avatar">$avatarChar</div>
        <div class="meta-details">
          <div class="sender-info">$escSenderName <span class="sender-email">&lt;$escSenderEmail&gt;</span></div>
          <div class="recipient-info">to $escToEmail</div>
        </div>
        <div class="date-info">$escDateStr</div>
      </div>
    </div>
    <div class="email-body">
      $processedBody
    </div>
  </div>
</body>
</html>
''';

    final encodedHtml = Uri.encodeComponent(pageHtml);
    js.context.callMethod('eval', ["""
      var win = window.open('', '_blank', 'width=900,height=750,scrollbars=yes,resizable=yes');
      if (win) {
        win.document.open();
        win.document.write(decodeURIComponent('$encodedHtml'));
        win.document.close();
      }
    """]);
  } catch (e) {
    // Ignore or log
  }
}
