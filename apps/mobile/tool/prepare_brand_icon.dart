import 'dart:io';

import 'package:image/image.dart' as image;

/// Removes nearly invisible stray pixels from the supplied transparent logo.
/// The visible artwork is left untouched; the launcher generator then creates
/// the Android and opaque iOS sizes from this reproducible source.
void main() {
  final File source = File('assets/branding/transpono.png');
  final image.Image? icon = image.decodePng(source.readAsBytesSync());
  if (icon == null) throw StateError('Não foi possível ler transpono.png.');

  for (int y = 0; y < icon.height; y++) {
    for (int x = 0; x < icon.width; x++) {
      if (icon.getPixel(x, y).a < 16) {
        icon.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  File('assets/branding/transpono_launcher.png')
      .writeAsBytesSync(image.encodePng(icon));
}
