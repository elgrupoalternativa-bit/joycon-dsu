// Versión app (APK Android / app iPhone): servidor DSU directo a la Xbox y,
// además, central para los iPhone que entran por la página web.
import 'dart:async';
import 'dart:io';

import 'package:sensors_plus/sensors_plus.dart';

import '../dsu/control_state.dart';
import '../dsu/dsu_server.dart';
import '../red/conexion.dart';
import 'comun.dart';

const esWeb = false;

/// En la app no hay que pedir permiso de movimiento con un toque.
Future<bool> pedirPermisoMovimiento() async => true;

Stream<Movimiento> movimientos() {
  // La app va siempre horizontal con la parte de arriba a la izquierda (90°).
  final c = StreamController<Movimiento>();
  double ax = 0, ay = 0, az = 9.8;
  StreamSubscription<dynamic>? s1, s2;
  c.onListen = () {
    s1 = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      ax = e.x;
      ay = e.y;
      az = e.z;
    });
    s2 = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      const aGrados = 57.29577951308232;
      c.add(aDsu(ax: ax, ay: ay, az: az, gx: e.x * aGrados, gy: e.y * aGrados, gz: e.z * aGrados, angulo: 90));
    });
  };
  c.onCancel = () {
    s1?.cancel();
    s2?.cancel();
  };
  return c.stream;
}

Salida crearSalida({
  required ControlState Function() leer,
  required void Function() alCambiar,
  required Stopwatch reloj,
}) =>
    _SalidaNativa(leer, alCambiar, reloj);

class _SalidaNativa implements Salida {
  _SalidaNativa(this._leer, this._alCambiar, Stopwatch reloj) {
    _central = Central(reloj: reloj, alCambiar: _alCambiar);
    // Puerto 26760: jugador 1 (este celular) y jugadores 2 a 4 (iPhone).
    _dsu1 = DsuServer(
      puerto: puertoDsu,
      leerEstado: (r) => r == 0 ? _leer() : _central.jugador(r),
    );
    // Puerto 26761: jugadores 5 a 8.
    _dsu2 = DsuServer(puerto: puertoDsu + 1, leerEstado: (r) => _central.jugador(r + 4));
    _dsu1.conectados.addListener(_alCambiar);
  }

  final ControlState Function() _leer;
  final void Function() _alCambiar;
  late final Central _central;
  late final DsuServer _dsu1, _dsu2;
  String _ip = '…';
  String? _error;

  @override
  Future<void> iniciar() async {
    try {
      await _dsu1.iniciar();
      await _dsu2.iniciar();
    } catch (e) {
      _error = 'No se pudo abrir el puerto DSU';
    }
    _ip = await _buscarIp();
    _alCambiar();
    // La central no bloquea: si no hay internet, el control igual funciona.
    unawaited(_central.iniciar());
  }

  @override
  Future<void> detener() async {
    await _dsu1.detener();
    await _dsu2.detener();
    await _central.detener();
  }

  @override
  bool get ok => _dsu1.conectados.value > 0;

  @override
  String get texto {
    if (_error != null) return _error!;
    final iphones = _central.remotos;
    final extra = iphones > 0 ? ' · +$iphones' : '';
    return ok ? 'Xbox ✓$extra' : '$_ip$extra';
  }

  @override
  String get ayuda {
    final c = switch (_central.estado) {
      'lista' => 'Este celular es la CENTRAL: los iPhone que abran el link en este Wi-Fi entran solos.',
      'otra' => 'Ya hay otra central en este Wi-Fi: los iPhone se conectan a esa.',
      'buscando' => 'Preparando la central…',
      _ => 'La central no pudo arrancar (¿hay internet?). Este control igual funciona.',
    };
    return 'En JADYX: Controles → Movimiento / DSU (cemuhook) → agrega el servidor\n'
        '   IP: $_ip   Puerto: $puertoDsu  (jugadores 1 a 4)\n'
        '   IP: $_ip   Puerto: ${puertoDsu + 1}  (jugadores 5 a 8)\n\n$c\n\n'
        'Celulares y Xbox en el mismo Wi-Fi. Deja la app abierta.';
  }

  Future<String> _buscarIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final nombre in ['wlan0', 'en0']) {
        for (final i in interfaces) {
          if (i.name == nombre && i.addresses.isNotEmpty) return i.addresses.first.address;
        }
      }
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && (a.address.startsWith('192.168.') || a.address.startsWith('10.'))) {
            return a.address;
          }
        }
      }
    } catch (_) {}
    return 'sin Wi-Fi';
  }
}
