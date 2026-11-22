import 'package:flutter_test/flutter_test.dart';
import 'package:joycon_dsu/ui/piezas.dart';

void main() {
  test('un roce en el centro no mueve nada', () {
    expect(curvaPalanca(0.1, 0.05), Offset.zero);
  });

  test('la mitad del recorrido da poco, el borde da el 100 %', () {
    final medio = curvaPalanca(0, 0.5);
    expect(medio.dy, greaterThan(0));
    expect(medio.dy, lessThan(0.35));
    final borde = curvaPalanca(0, -1);
    expect(borde.dy, closeTo(-1, 1e-9));
    expect(borde.dx.abs(), lessThan(1e-9));
  });

  test('conserva la dirección', () {
    final r = curvaPalanca(0.6, 0.6);
    expect(r.dx, closeTo(r.dy, 1e-9));
    expect(r.dx, greaterThan(0));
  });
}
