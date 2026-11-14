import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/user_message.dart';

void main() {
  test('own Portuguese messages lose the English prefix', () {
    expect(
      userMessage(StateError('Autorize o microfone nas definições.')),
      'Autorize o microfone nas definições.',
    );
    expect(
      userMessage(const SocketException('Ligue o telemóvel à rede Wi-Fi.')),
      'Ligue o telemóvel à rede Wi-Fi.',
    );
  });

  test('technical English errors become a generic sentence', () {
    expect(
      userMessage(StateError('Native audio did not play.')),
      'Ocorreu um erro inesperado. Tente novamente.',
    );
    expect(
      userMessage(PlatformException(code: 'x', message: 'channel error')),
      'Ocorreu um erro inesperado. Tente novamente.',
    );
    expect(userMessage(Exception('boom')), contains('Tente novamente'));
  });
}
