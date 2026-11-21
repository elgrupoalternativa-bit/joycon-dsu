// CRC32 estándar (polinomio reflejado 0xEDB88320), el que exige DSU.
import 'dart:typed_data';

final Uint32List _tabla = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[i] = c;
  }
  return t;
}();

int crc32(Uint8List datos) {
  var c = 0xFFFFFFFF;
  for (final b in datos) {
    c = _tabla[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
