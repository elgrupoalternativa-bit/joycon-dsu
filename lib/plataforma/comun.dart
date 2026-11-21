// Lo que comparten la versión app (Android/iPhone) y la versión página web.
import '../dsu/control_state.dart';

/// Hacia dónde va el control: a la Xbox directo (app) o a la central (web).
abstract class Salida {
  Future<void> iniciar();
  Future<void> detener();

  /// Texto corto para la píldora de arriba.
  String get texto;

  /// Verde = todo conectado.
  bool get ok;

  /// Texto largo para la pantalla de ajustes.
  String get ayuda;
}

typedef CrearSalida = Salida Function({
  required ControlState Function() leer,
  required void Function() alCambiar,
  required Stopwatch reloj,
});

/// Una lectura de movimiento ya en ejes DSU: X derecha, Y arriba, Z hacia el
/// jugador. Aceleración en g, giro en grados por segundo.
class Movimiento {
  Movimiento(this.ax, this.ay, this.az, this.pitch, this.yaw, this.roll);
  final double ax, ay, az, pitch, yaw, roll;
}

/// Convierte de ejes del teléfono (vertical: X derecha, Y arriba, Z fuera de la
/// pantalla; aceleración con la gravedad hacia +Z cuando está acostado boca
/// arriba) a ejes DSU, según cómo esté girada la pantalla.
///
/// [angulo]: 90 = acostado con la parte de arriba del teléfono a la izquierda,
/// −90 = arriba a la derecha, 0 = vertical.
Movimiento aDsu({
  required double ax, required double ay, required double az, // m/s²
  required double gx, required double gy, required double gz, // °/s
  required int angulo,
}) {
  const g = 9.80665;
  double derA, lejosA, derG, lejosG;
  switch (angulo) {
    case 90:
      derA = -ay; lejosA = ax; derG = -gy; lejosG = gx;
    case -90:
    case 270:
      derA = ay; lejosA = -ax; derG = gy; lejosG = -gx;
    case 180:
      derA = -ax; lejosA = -ay; derG = -gx; lejosG = -gy;
    default:
      derA = ax; lejosA = ay; derG = gx; lejosG = gy;
  }
  return Movimiento(derA / g, az / g, -lejosA / g, derG, gz, -lejosG);
}
