import 'dart:io';

import 'package:flutter/services.dart';

/// The text of an error, fit to show to the user: the app's own messages
/// (already in Portuguese) without Dart's English prefixes ("Bad state:",
/// "SocketException:", "PlatformException(…)"); anything else becomes a
/// short generic sentence instead of technical text.
String userMessage(Object error) {
  final String? own = switch (error) {
    StateError(:final message) => message,
    ArgumentError(:final message) => message is String ? message : null,
    FormatException(:final message) => message,
    SocketException(:final message) => message,
    PlatformException(:final message) => message,
    _ => null,
  };
  if (own != null && own.trim().isNotEmpty && _looksPortuguese(own)) {
    return own.trim();
  }
  return 'Ocorreu um erro inesperado. Tente novamente.';
}

// The app's messages carry Portuguese letters or common words; system and
// library messages are in English.
bool _looksPortuguese(String text) =>
    RegExp(r'[ãõçáéíóúâêôà]', caseSensitive: false).hasMatch(text) ||
    RegExp(
      r'\b(não|nao|abra|ligue|tente|autorize|escolha|use|guardar|coleção|item)\b',
      caseSensitive: false,
    ).hasMatch(text);
