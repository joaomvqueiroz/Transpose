import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (Map<String, dynamic>? data) async {
    final Directory directory = Directory('build');
    await directory.create(recursive: true);
    await File('${directory.path}/main_panel_evidence.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
