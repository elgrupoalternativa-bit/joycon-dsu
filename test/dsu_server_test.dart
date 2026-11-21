import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycon_dsu/dsu/control_state.dart';
import 'package:joycon_dsu/dsu/crc32.dart';
import 'package:joycon_dsu/dsu/dsu_server.dart';

/// Arma un mensaje de cliente (como lo manda el emulador).
Uint8List _pedido(int tipo, List<int> carga) {
  final r = ByteData(20 + carga.length);
  r.setUint8(0, 0x44);
  r.setUint8(1, 0x53);
  r.setUint8(2, 0x55);
  r.setUint8(3, 0x43); // DSUC
  r.setUint16(4, 1001, Endian.little);
  r.setUint16(6, 4 + carga.length, Endian.little);
  r.setUint32(12, 1234, Endian.little);
  r.setUint32(16, tipo, Endian.little);
  for (var i = 0; i < carga.length; i++) {
    r.setUint8(20 + i, carga[i]);
  }
  final b = r.buffer.asUint8List();
  r.setUint32(8, crc32(b), Endian.little);
  return b;
}

bool _crcBien(Uint8List p) {
  final copia = Uint8List.fromList(p);
  final bd = ByteData.sublistView(copia);
  final dado = bd.getUint32(8, Endian.little);
  bd.setUint32(8, 0, Endian.little);
  return crc32(copia) == dado;
}

void main() {
  test('CRC32 conocido', () {
    expect(crc32(Uint8List.fromList('123456789'.codeUnits)), 0xCBF43926);
  });

  test('responde info y manda datos de 100 bytes con botones, palanca y giroscopio', () async {
    final estado = ControlState()
      ..a = true
      ..zr = true
      ..arriba = true
      ..izqY = 1.0 // palanca izquierda totalmente ARRIBA
      ..gyroYaw = 90.0
      ..accelY = 1.0;
    final srv = DsuServer(leerEstado: () => estado);
    await srv.iniciar();

    final cli = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final recibidos = <Uint8List>[];
    cli.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = cli.receive();
        if (d != null) recibidos.add(d.data);
      }
    });

    // 1) info de la ranura 0
    cli.send(_pedido(0x100001, [1, 0, 0, 0, 0]), InternetAddress.loopbackIPv4, puertoDsu);
    // 2) suscribirse a datos
    cli.send(_pedido(0x100002, [0, 0, 0, 0, 0, 0, 0, 0]), InternetAddress.loopbackIPv4, puertoDsu);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await srv.detener();
    cli.close();

    final info = recibidos.firstWhere((p) => ByteData.sublistView(p).getUint32(16, Endian.little) == 0x100001);
    expect(info.length, 32);
    expect(info[21], 2, reason: 'ranura 0 anunciada como conectada');
    expect(_crcBien(info), isTrue);

    final datos = recibidos.where((p) => ByteData.sublistView(p).getUint32(16, Endian.little) == 0x100002).toList();
    expect(datos.length, greaterThan(5), reason: 'debe mandar a ~60 Hz');
    final p = datos.last;
    final bd = ByteData.sublistView(p);
    expect(p.length, 100);
    expect(String.fromCharCodes(p.sublist(0, 4)), 'DSUS');
    expect(_crcBien(p), isTrue);
    expect(p[36] & 0x10, 0x10, reason: 'cruceta arriba');
    expect(p[37] & 0x20, 0x20, reason: 'A = posición este');
    expect(p[37] & 0x02, 0x02, reason: 'ZR');
    expect(p[41], 255, reason: 'palanca arriba = 255 (no al revés)');
    expect(p[40], 128, reason: 'palanca X al centro');
    expect(bd.getFloat32(80, Endian.little), closeTo(1.0, 1e-6), reason: 'accel Y');
    expect(bd.getFloat32(92, Endian.little), closeTo(90.0, 1e-4), reason: 'gyro yaw');
  });
}
