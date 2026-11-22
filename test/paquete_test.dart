import 'package:flutter_test/flutter_test.dart';
import 'package:joycon_dsu/dsu/control_state.dart';
import 'package:joycon_dsu/plataforma/comun.dart';
import 'package:joycon_dsu/red/paquete.dart';

void main() {
  test('el paquete del iPhone ida y vuelta conserva todo', () {
    final e = ControlState()
      ..a = true
      ..derecha = true
      ..zl = true
      ..home = true
      ..izqX = -1
      ..izqY = 0.5
      ..gyroRoll = -123.5
      ..accelZ = 0.25;
    final bytes = codificar(e);
    expect(bytes.length, 32);
    final r = ControlState();
    expect(decodificar(bytes, r, 777), isTrue);
    expect([r.a, r.derecha, r.zl, r.home, r.b, r.izquierda], [true, true, true, true, false, false]);
    expect(r.izqX, closeTo(-1, 0.01));
    expect(r.izqY, closeTo(0.5, 0.01));
    expect(r.gyroRoll, closeTo(-123.5, 1e-3));
    expect(r.accelZ, closeTo(0.25, 1e-6));
    expect(r.tiempoMicros, 777);
  });

  test('celular acostado boca arriba: la gravedad queda en −Y de DSU (calibrado en JADYX)', () {
    for (final ang in [0, 90, -90]) {
      final m = aDsu(ax: 0, ay: 0, az: 9.80665, gx: 0, gy: 0, gz: 0, angulo: ang);
      expect(m.ay, closeTo(-1, 1e-6));
      expect(m.ax.abs() + m.az.abs(), closeTo(0, 1e-6));
    }
  });

  test('horizontal a 90°: girar sobre el eje largo del teléfono es el pitch', () {
    // El eje Y del teléfono (su largo) apunta a la izquierda del jugador.
    final m = aDsu(ax: 0, ay: 0, az: 9.8, gx: 0, gy: 50, gz: 0, angulo: 90);
    expect(m.pitch, closeTo(50, 1e-6));
    expect(m.yaw.abs(), 0);
    expect(m.roll, closeTo(0, 1e-9));
  });
}
