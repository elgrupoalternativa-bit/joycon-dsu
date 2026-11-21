// El "cerebro" de la app: junta los sensores, los toques y el servidor DSU.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'dsu/control_state.dart';
import 'dsu/dsu_server.dart';

enum ModoControl { dosJoycon, joyconIzquierdo, joyconDerecho }

class ColorJoycon {
  const ColorJoycon(this.nombre, this.valor);
  final String nombre;
  final int valor;
}

const coloresJoycon = [
  ColorJoycon('Rojo neón', 0xFFFF3C28),
  ColorJoycon('Azul neón', 0xFF0AB9E6),
  ColorJoycon('Amarillo', 0xFFE6FF00),
  ColorJoycon('Verde', 0xFF1EDC00),
  ColorJoycon('Rosado', 0xFFFF3278),
  ColorJoycon('Morado', 0xFFB400E6),
  ColorJoycon('Gris', 0xFF828282),
];

/// Ajustes de ejes del movimiento. Cada teléfono y cada emulador pueden
/// interpretar los ejes distinto, así que se pueden voltear desde la app.
class AjustesMovimiento {
  bool invertirPitch = false;
  bool invertirYaw = false;
  bool invertirRoll = false;
  bool invertirPalancaY = false;
  double sensibilidad = 1.0;
}

class ControlApp extends ChangeNotifier {
  ControlApp() {
    _servidor = DsuServer(leerEstado: () => estado);
    _servidor.conectados.addListener(notifyListeners);
  }

  final ControlState estado = ControlState();
  final AjustesMovimiento movimiento = AjustesMovimiento();
  late final DsuServer _servidor;

  ModoControl modo = ModoControl.dosJoycon;
  int colorIzq = coloresJoycon[1].valor; // azul a la izquierda, como el Switch
  int colorDer = coloresJoycon[0].valor; // rojo a la derecha
  String ip = 'buscando…';
  String? error;

  int get emuladoresConectados => _servidor.conectados.value;

  final _subs = <StreamSubscription<dynamic>>[];
  final _reloj = Stopwatch()..start();

  Future<void> iniciar() async {
    try {
      await _servidor.iniciar();
    } catch (e) {
      error = 'No se pudo abrir el puerto $puertoDsu: $e';
    }
    _subs.add(
      accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_alAcelerar),
    );
    _subs.add(
      gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_alGirar),
    );
    ip = await _buscarIp();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _servidor.detener();
    super.dispose();
  }

  // El celular va acostado (horizontal) con la parte de arriba hacia la
  // izquierda. Ejes del teléfono (vertical): X a la derecha, Y hacia arriba,
  // Z saliendo de la pantalla. Ejes DSU: X derecha, Y arriba, Z hacia el jugador.
  //   DSU X = −teléfono Y,  DSU Y = teléfono Z,  DSU Z = −teléfono X
  void _alAcelerar(AccelerometerEvent e) {
    const g = 9.80665;
    estado.accelX = -e.y / g;
    estado.accelY = e.z / g;
    estado.accelZ = -e.x / g;
    estado.tiempoMicros = _reloj.elapsedMicroseconds;
  }

  void _alGirar(GyroscopeEvent e) {
    const aGrados = 57.29577951308232;
    final s = movimiento.sensibilidad * aGrados;
    estado.gyroPitch = -e.y * s * (movimiento.invertirPitch ? -1 : 1);
    estado.gyroYaw = e.z * s * (movimiento.invertirYaw ? -1 : 1);
    estado.gyroRoll = -e.x * s * (movimiento.invertirRoll ? -1 : 1);
    estado.tiempoMicros = _reloj.elapsedMicroseconds;
  }

  // ----------------------------------------------------------------- toques

  void boton(String nombre, bool presionado) {
    switch (nombre) {
      case 'A': estado.a = presionado;
      case 'B': estado.b = presionado;
      case 'X': estado.x = presionado;
      case 'Y': estado.y = presionado;
      case 'L': estado.l = presionado;
      case 'R': estado.r = presionado;
      case 'ZL': estado.zl = presionado;
      case 'ZR': estado.zr = presionado;
      case '+': estado.mas = presionado;
      case '−': estado.menos = presionado;
      case 'HOME': estado.home = presionado;
      case 'CAPT': estado.captura = presionado;
      case 'L3': estado.l3 = presionado;
      case 'R3': estado.r3 = presionado;
      case '↑': estado.arriba = presionado;
      case '↓': estado.abajo = presionado;
      case '←': estado.izquierda = presionado;
      case '→': estado.derecha = presionado;
    }
    if (presionado) HapticFeedback.lightImpact();
  }

  /// x, y entre −1 y 1, con y positivo hacia ARRIBA.
  void palanca({required bool izquierda, required double x, required double y}) {
    final yy = movimiento.invertirPalancaY ? -y : y;
    if (izquierda) {
      estado.izqX = x;
      estado.izqY = yy;
    } else {
      estado.derX = x;
      estado.derY = yy;
    }
  }

  void cambiarModo(ModoControl m) {
    modo = m;
    notifyListeners();
  }

  void cambiarColor({required bool izquierdo, required int color}) {
    if (izquierdo) {
      colorIzq = color;
    } else {
      colorDer = color;
    }
    notifyListeners();
  }

  void avisar() => notifyListeners();

  Future<String> _buscarIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      // Primero el Wi-Fi (en0 en iPhone, wlan0 en Android).
      for (final nombre in ['en0', 'wlan0']) {
        for (final i in interfaces) {
          if (i.name == nombre && i.addresses.isNotEmpty) return i.addresses.first.address;
        }
      }
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && a.address.startsWith('192.168.')) return a.address;
        }
      }
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return 'sin Wi-Fi';
  }
}
