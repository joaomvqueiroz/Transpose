import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

/// Generates launcher artwork from the two user-supplied root images.
/// Day uses transpono1; Android's night-qualified resources use transpono2.
void main() {
  final day = _square('../../transpono1.png');
  final night = _square('../../transpono2.png');
  _write('assets/branding/transpono_launcher.png', day);
  _write('assets/branding/transpono_adaptive.png', day);
  _write('assets/branding/transpono_launcher_night.png', night);
  _write('assets/branding/transpono_adaptive_night.png', night);
  const iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  _write('$iosIcons/Icon-App-1024x1024-dark.png', night);
  final contentsFile = File('$iosIcons/Contents.json');
  final contents =
      jsonDecode(contentsFile.readAsStringSync()) as Map<String, dynamic>;
  final images = (contents['images'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  images.removeWhere(
    (entry) => entry['filename'] == 'Icon-App-1024x1024-dark.png',
  );
  images.add(<String, dynamic>{
    'size': '1024x1024',
    'idiom': 'universal',
    'platform': 'ios',
    'filename': 'Icon-App-1024x1024-dark.png',
    'appearances': [
      {'appearance': 'luminosity', 'value': 'dark'},
    ],
  });
  contentsFile.writeAsStringSync(jsonEncode(contents));

  const densities = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in densities.entries) {
    _write(
      'android/app/src/main/res/mipmap-night-${entry.key}/ic_launcher.png',
      image.copyResize(night, width: entry.value, height: entry.value),
    );
    _write(
      'android/app/src/main/res/drawable-night-${entry.key}/ic_launcher_foreground.png',
      image.copyResize(night, width: entry.value * 2, height: entry.value * 2),
    );
  }
}

image.Image _square(String path) {
  final source = image.decodeImage(File(path).readAsBytesSync());
  if (source == null) throw StateError('Imagem inválida: $path');
  final canvas = image.Image(width: 1024, height: 1024);
  image.fill(canvas, color: image.ColorRgb8(0, 0, 0));
  final fitted = image.copyResize(source, width: 1024);
  image.compositeImage(
    canvas,
    fitted,
    dstY: (canvas.height - fitted.height) ~/ 2,
  );
  return canvas;
}

void _write(String path, image.Image icon) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(image.encodePng(icon));
}
