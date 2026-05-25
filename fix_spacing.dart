import 'dart:io';

void main() {
  var f = File('lib/login_screen.dart');
  var c = f.readAsStringSync();
  c = c.replaceAll('const SizedBox(height: 24),', 'SizedBox(height: isMobile ? 12 : 24),');
  c = c.replaceAll('const SizedBox(height: 32),', 'SizedBox(height: isMobile ? 16 : 32),');
  c = c.replaceAll('const SizedBox(height: 20),', 'SizedBox(height: isMobile ? 12 : 20),');
  c = c.replaceAll('const SizedBox(height: 16),', 'SizedBox(height: isMobile ? 8 : 16),');
  c = c.replaceAll('size: 48,', 'size: isMobile ? 36 : 48,');
  f.writeAsStringSync(c);
  print('Done! Spacing reduced for mobile.');
}
