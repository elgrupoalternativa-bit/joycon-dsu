// El "cerebro" de la app: junta los sensores, los toques y la salida
// (directo a la Xbox en la app, o hacia la central en la página web).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dsu/control_state.dart';
import 'plataforma/comun.dart';
import 'plataforma/plataforma.dart' as plataforma;

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
    salida = plataforma.crearSalida(leer: () => estado, alCambiar: notifyListeners, reloj: _reloj);
  }

  static const esWeb = plataforma.esWeb;

  final ControlState estado = ControlState();
  final AjustesMovimiento movimiento = AjustesMovimiento();
  late final Salida salida;

  ModoControl modo = ModoControl.dosJoycon;
  int colorIzq = coloresJoycon[1].valor; // azul a la izquierda, como el Switch
  int colorDer = coloresJoycon[0].valor; // rojo a la derecha

  /// En la web hay que tocar un botón antes de arrancar (permiso de movimiento).
  bool arrancado = false;
  bool sinMovimiento = false;

  final _reloj = Stopwatch()..start();
  StreamSubscription<Movimiento>? _sub;

  /// En la app arranca solo; en la web, al tocar "Empezar".
  Future<void> arrancar() async {
    if (arrancado) return;
    // Si el navegador nunca contesta, seguimos igual (sin giroscopio).
    final permiso = await plataforma
        .pedirPermisoMovimiento()
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    sinMovimiento = !permiso;
    _sub = plataforma.movimientos().listen(_alMover);
    arrancado = true;
    notifyListeners();
    await salida.iniciar();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    salida.detener();
    super.dispose();
  }

  void _alMover(Movimiento m) {
    final s = movimiento.sensibilidad;
    estado
      ..accelX = m.ax
      ..accelY = m.ay
      ..accelZ = m.az
      ..gyroPitch = m.pitch * s * (movimiento.invertirPitch ? -1 : 1)
      ..gyroYaw = m.yaw * s * (movimiento.invertirYaw ? -1 : 1)
      ..gyroRoll = m.roll * s * (movimiento.invertirRoll ? -1 : 1)
      ..tiempoMicros = _reloj.elapsedMicroseconds;
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
    if (presionado) {
      HapticFeedback.lightImpact();
      salida.despertar();
    }
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
}
