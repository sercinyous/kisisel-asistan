import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget testlerinde varsayılan "FlutterTest" yazı tipi her harfi kare çizer
/// ve metinleri gerçekte olduğundan çok daha geniş ölçer; taşma (overflow)
/// testleri bu yüzden yanlış alarm verir. Flutter SDK ile gelen Roboto'yu
/// yükleyerek gerçeğe yakın genişlikler elde ederiz.
///
/// SDK önbelleğinde yazı tipi bulunamazsa `false` döner (test atlanmalıdır).
Future<bool> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;

  Future<ByteData> read(String name) async {
    final bytes = await File('${dir.path}/$name').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final roboto = FontLoader('Roboto');
  for (final file in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    if (!File('${dir.path}/$file').existsSync()) return false;
    roboto.addFont(read(file));
  }
  await roboto.load();

  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(read('MaterialIcons-Regular.otf'));
    await loader.load();
  }
  return true;
}
