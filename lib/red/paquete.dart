// Formato del paquete que un control remoto (iPhone por la web) le manda a la
// central Android por WebRTC. 32 bytes, ~60 veces por segundo.
//
//  0     versión (1)
//  1..3  botones (bits)
//  4..7  palancas izqX, izqY, derX, derY como int8 (−127..127)
//  8..31 accelX, accelY, accelZ (g), gyroPitch, gyroYaw, gyroRoll (°/s), float32
import 'dart:typed_data';

import '../dsu/control_state.dart';

const _orden = [
  'a', 'b', 'x', 'y', 'l', 'r', 'zl', 'zr', //
  'mas', 'menos', 'home', 'captura', 'l3', 'r3', //
  'arriba', 'abajo', 'izquierda', 'derecha',
];

List<bool> _leerBotones(ControlState e) => [
      e.a, e.b, e.x, e.y, e.l, e.r, e.zl, e.zr, //
      e.mas, e.menos, e.home, e.captura, e.l3, e.r3, //
      e.arriba, e.abajo, e.izquierda, e.derecha,
    ];

void _ponerBotones(ControlState e, List<bool> v) {
  e
    ..a = v[0]
    ..b = v[1]
    ..x = v[2]
    ..y = v[3]
    ..l = v[4]
    ..r = v[5]
    ..zl = v[6]
    ..zr = v[7]
    ..mas = v[8]
    ..menos = v[9]
    ..home = v[10]
    ..captura = v[11]
    ..l3 = v[12]
    ..r3 = v[13]
    ..arriba = v[14]
    ..abajo = v[15]
    ..izquierda = v[16]
    ..derecha = v[17];
}

int _i8(double v) => (v.clamp(-1.0, 1.0) * 127).round();

Uint8List codificar(ControlState e) {
  final b = ByteData(32);
  b.setUint8(0, 1);
  final botones = _leerBotones(e);
  var bits = 0;
  for (var i = 0; i < botones.length; i++) {
    if (botones[i]) bits |= 1 << i;
  }
  b.setUint8(1, bits & 0xff);
  b.setUint8(2, (bits >> 8) & 0xff);
  b.setUint8(3, (bits >> 16) & 0xff);
  b.setInt8(4, _i8(e.izqX));
  b.setInt8(5, _i8(e.izqY));
  b.setInt8(6, _i8(e.derX));
  b.setInt8(7, _i8(e.derY));
  b.setFloat32(8, e.accelX, Endian.little);
  b.setFloat32(12, e.accelY, Endian.little);
  b.setFloat32(16, e.accelZ, Endian.little);
  b.setFloat32(20, e.gyroPitch, Endian.little);
  b.setFloat32(24, e.gyroYaw, Endian.little);
  b.setFloat32(28, e.gyroRoll, Endian.little);
  return b.buffer.asUint8List();
}

/// Copia el paquete dentro de [e]. Devuelve false si no es un paquete válido.
bool decodificar(Uint8List datos, ControlState e, int tiempoMicros) {
  if (datos.length < 32 || datos[0] != 1) return false;
  final b = ByteData.sublistView(datos);
  final bits = b.getUint8(1) | (b.getUint8(2) << 8) | (b.getUint8(3) << 16);
  _ponerBotones(e, [for (var i = 0; i < _orden.length; i++) (bits & (1 << i)) != 0]);
  e
    ..izqX = b.getInt8(4) / 127
    ..izqY = b.getInt8(5) / 127
    ..derX = b.getInt8(6) / 127
    ..derY = b.getInt8(7) / 127
    ..accelX = b.getFloat32(8, Endian.little)
    ..accelY = b.getFloat32(12, Endian.little)
    ..accelZ = b.getFloat32(16, Endian.little)
    ..gyroPitch = b.getFloat32(20, Endian.little)
    ..gyroYaw = b.getFloat32(24, Endian.little)
    ..gyroRoll = b.getFloat32(28, Endian.little)
    ..tiempoMicros = tiempoMicros;
  return true;
}
