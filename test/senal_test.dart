import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycon_dsu/red/senal.dart';

/// La fórmula vieja: exacta en la app (enteros de 64 bits), la que ya usa la
/// central instalada en los celulares.
int _viejaNativa(String texto) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(texto)) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

void main() {
  test('el nombre nuevo es idéntico al que calcula la central ya instalada', () {
    for (final ip in ['181.49.12.200', '190.24.3.7', '8.8.8.8', '2800:e2:1a80::1', '']) {
      final t = 'joycon-dsu|$ip|';
      expect(fnv1a32(t), _viejaNativa(t), reason: ip);
    }
  });

  test('cada multiplicación queda por debajo de 2^53 (segura en JavaScript)', () {
    expect(0xffffffff * 0x193 + 0xff000000, lessThan(1 << 53));
  });
}
