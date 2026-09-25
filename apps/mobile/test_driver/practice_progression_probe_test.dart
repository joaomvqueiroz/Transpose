import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (Map<String, dynamic>? data) async {
    final directory = Directory('build');
    await directory.create(recursive: true);
    await File('${directory.path}/practice_progression_evidence.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
