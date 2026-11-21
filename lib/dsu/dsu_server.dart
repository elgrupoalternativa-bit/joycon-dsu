// Servidor DSU (protocolo "cemuhook") que corre en el celular.
//
// El emulador (JADYX / Eden / yuzu) es el CLIENTE: se conecta a la IP del
// celular, puerto 26760, pide la información del control y luego se suscribe a
// los datos. Mientras siga pidiendo, le mandamos ~60 paquetes por segundo con
// botones, palancas, acelerómetro y giroscopio.
//
// Referencia del protocolo: https://github.com/v1993/cemuhook-protocol
// Paquete de datos: 100 bytes (cabecera 16 + tipo 4 + carga 80).

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'control_state.dart';
import 'crc32.dart';

const int puertoDsu = 26760;
const int _versionProtocolo = 1001;

const int _msgVersion = 0x100000;
const int _msgInfo = 0x100001;
const int _msgDatos = 0x100002;

/// Un cliente (el emulador) que pidió datos hace poco.
class _Suscriptor {
  _Suscriptor(this.direccion, this.puerto);
  final InternetAddress direccion;
  final int puerto;
  DateTime ultimaPeticion = DateTime.now();
  String get clave => '${direccion.address}:$puerto';
}

class DsuServer {
  DsuServer({required this.leerEstado, this.puerto = puertoDsu});

  /// Estado del control en cada ranura (0..3) de ESTE servidor, o null si en
  /// esa ranura no hay nadie conectado.
  final ControlState? Function(int ranura) leerEstado;

  /// 26760 = jugadores 1 a 4; 26761 = jugadores 5 a 8.
  final int puerto;

  final int _idServidor = Random().nextInt(0x7fffffff);
  final Map<String, _Suscriptor> _suscriptores = {};
  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Para mostrar en pantalla si el emulador está conectado.
  final ValueNotifierLite<int> conectados = ValueNotifierLite(0);

  // MAC falsa pero estable para este servidor.
  final List<int> _numeroPorRanura = [0, 0, 0, 0];

  Uint8List _mac(int ranura) => Uint8List.fromList([
        0x4a, // "J"
        0x30 + ranura,
        (_idServidor >> 24) & 0xff,
        (_idServidor >> 16) & 0xff,
        (_idServidor >> 8) & 0xff,
        _idServidor & 0xff,
      ]);

  Future<void> iniciar() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puerto);
    _socket!.listen((evento) {
      if (evento != RawSocketEvent.read) return;
      final dg = _socket!.receive();
      if (dg != null) _recibir(dg);
    });
    // ~60 Hz, como un control real.
    _timer = Timer.periodic(const Duration(microseconds: 16667), (_) => _enviarDatos());
  }

  Future<void> detener() async {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
    _suscriptores.clear();
    conectados.value = 0;
  }

  // ---------------------------------------------------------------- recepción

  void _recibir(Datagram dg) {
    final d = dg.data;
    if (d.length < 20) return;
    // Magic "DSUC"
    if (d[0] != 0x44 || d[1] != 0x53 || d[2] != 0x55 || d[3] != 0x43) return;
    final bd = ByteData.sublistView(d);
    final tipo = bd.getUint32(16, Endian.little);

    switch (tipo) {
      case _msgVersion:
        final r = _nuevoPaquete(_msgVersion, 2);
        r.setUint16(20, _versionProtocolo, Endian.little);
        _enviar(r, dg.address, dg.port);
        break;

      case _msgInfo:
        if (d.length < 24) return;
        final cantidad = bd.getInt32(20, Endian.little).clamp(0, 4);
        for (var i = 0; i < cantidad && 24 + i < d.length; i++) {
          final pedido = d[24 + i];
          final r = _nuevoPaquete(_msgInfo, 12);
          _escribirCompartido(r, pedido, conectado: pedido < 4 && leerEstado(pedido) != null);
          r.setUint8(31, 0);
          _enviar(r, dg.address, dg.port);
        }
        break;

      case _msgDatos:
        final clave = '${dg.address.address}:${dg.port}';
        final s = _suscriptores.putIfAbsent(clave, () => _Suscriptor(dg.address, dg.port));
        s.ultimaPeticion = DateTime.now();
        conectados.value = _suscriptores.length;
        break;
    }
  }

  // ------------------------------------------------------------------- envío

  void _enviarDatos() {
    if (_socket == null || _suscriptores.isEmpty) return;

    // El emulador repite la petición cada ~1 s; si deja de pedir 5 s, lo soltamos.
    final ahora = DateTime.now();
    _suscriptores.removeWhere((_, s) => ahora.difference(s.ultimaPeticion).inSeconds > 5);
    conectados.value = _suscriptores.length;
    if (_suscriptores.isEmpty) return;

    for (var ranura = 0; ranura < 4; ranura++) {
      final e = leerEstado(ranura);
      if (e == null) continue;
      final p = _paqueteDatos(ranura, e);
      for (final s in _suscriptores.values) {
        _enviar(p, s.direccion, s.puerto, yaFirmado: true);
      }
    }
  }

  ByteData _paqueteDatos(int ranura, ControlState e) {
    final r = _nuevoPaquete(_msgDatos, 80);
    _escribirCompartido(r, ranura, conectado: true); // bytes 20..30
    r.setUint8(31, 1); // conectado
    r.setUint32(32, _numeroPorRanura[ranura]++, Endian.little);

    // Botones 1 (estilo DS4): cruceta, +/−, palancas presionadas.
    var b1 = 0;
    if (e.izquierda) b1 |= 0x80;
    if (e.abajo) b1 |= 0x40;
    if (e.derecha) b1 |= 0x20;
    if (e.arriba) b1 |= 0x10;
    if (e.mas) b1 |= 0x08; // Options → +
    if (e.r3) b1 |= 0x04;
    if (e.l3) b1 |= 0x02;
    if (e.menos) b1 |= 0x01; // Share → −

    // Botones 2. El emulador traduce por POSICIÓN, como en un control de Switch:
    // Y (oeste) = Cuadrado, B (sur) = Cruz, A (este) = Círculo, X (norte) = Triángulo.
    var b2 = 0;
    if (e.y) b2 |= 0x80;
    if (e.b) b2 |= 0x40;
    if (e.a) b2 |= 0x20;
    if (e.x) b2 |= 0x10;
    if (e.r) b2 |= 0x08;
    if (e.l) b2 |= 0x04;
    if (e.zr) b2 |= 0x02;
    if (e.zl) b2 |= 0x01;

    r.setUint8(36, b1);
    r.setUint8(37, b2);
    r.setUint8(38, e.home ? 1 : 0);
    r.setUint8(39, e.captura ? 1 : 0);

    // Palancas: 0..255, 128 al centro. En DSU el eje Y crece hacia ARRIBA
    // (ese era el error de la otra app: lo mandaba al revés).
    r.setUint8(40, _eje(e.izqX));
    r.setUint8(41, _eje(e.izqY));
    r.setUint8(42, _eje(e.derX));
    r.setUint8(43, _eje(e.derY));

    // Analógicos de botones (44..55): 255 presionado, 0 suelto.
    final analogos = [
      e.izquierda, e.abajo, e.derecha, e.arriba, //
      e.y, e.b, e.a, e.x, //
      e.r, e.l, e.zr, e.zl,
    ];
    for (var i = 0; i < analogos.length; i++) {
      r.setUint8(44 + i, analogos[i] ? 255 : 0);
    }
    // Táctil (56..67) en cero.

    // Movimiento: marca de tiempo en microsegundos, acelerómetro en g,
    // giroscopio en grados por segundo (pitch, yaw, roll).
    r.setUint64(68, e.tiempoMicros, Endian.little);
    r.setFloat32(76, e.accelX, Endian.little);
    r.setFloat32(80, e.accelY, Endian.little);
    r.setFloat32(84, e.accelZ, Endian.little);
    r.setFloat32(88, e.gyroPitch, Endian.little);
    r.setFloat32(92, e.gyroYaw, Endian.little);
    r.setFloat32(96, e.gyroRoll, Endian.little);

    _firmar(r);
    return r;
  }

  int _eje(double v) => (128 + v.clamp(-1.0, 1.0) * 127).round().clamp(0, 255);

  /// Cabecera de 16 bytes + tipo de mensaje. `carga` = bytes después del tipo.
  ByteData _nuevoPaquete(int tipo, int carga) {
    final r = ByteData(20 + carga);
    r.setUint8(0, 0x44); // D
    r.setUint8(1, 0x53); // S
    r.setUint8(2, 0x55); // U
    r.setUint8(3, 0x53); // S
    r.setUint16(4, _versionProtocolo, Endian.little);
    r.setUint16(6, 4 + carga, Endian.little); // largo sin la cabecera
    r.setUint32(8, 0, Endian.little); // CRC, se llena al final
    r.setUint32(12, _idServidor, Endian.little);
    r.setUint32(16, tipo, Endian.little);
    return r;
  }

  /// Bloque compartido de 11 bytes en el offset 20.
  void _escribirCompartido(ByteData r, int ranura, {required bool conectado}) {
    r.setUint8(20, ranura);
    r.setUint8(21, conectado ? 2 : 0); // 2 = conectado
    r.setUint8(22, conectado ? 2 : 0); // 2 = giroscopio completo
    r.setUint8(23, conectado ? 2 : 0); // 2 = bluetooth
    final mac = _mac(ranura & 3);
    for (var i = 0; i < 6; i++) {
      r.setUint8(24 + i, conectado ? mac[i] : 0);
    }
    r.setUint8(30, conectado ? 0x05 : 0x00); // batería llena
  }

  void _firmar(ByteData r) {
    r.setUint32(8, 0, Endian.little);
    final bytes = r.buffer.asUint8List(r.offsetInBytes, r.lengthInBytes);
    r.setUint32(8, crc32(bytes), Endian.little);
  }

  void _enviar(ByteData r, InternetAddress a, int puerto, {bool yaFirmado = false}) {
    if (!yaFirmado) _firmar(r);
    _socket?.send(r.buffer.asUint8List(r.offsetInBytes, r.lengthInBytes), a, puerto);
  }
}

/// Un ValueNotifier mínimo para no depender de Flutter en esta capa
/// (así se puede probar con `dart test` sin emulador).
class ValueNotifierLite<T> {
  ValueNotifierLite(this._value);
  T _value;
  final _oyentes = <void Function()>[];
  T get value => _value;
  set value(T v) {
    if (v == _value) return;
    _value = v;
    for (final o in List.of(_oyentes)) {
      o();
    }
  }

  void addListener(void Function() f) => _oyentes.add(f);
  void removeListener(void Function() f) => _oyentes.remove(f);
}
