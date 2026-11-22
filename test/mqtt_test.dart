import 'package:flutter_test/flutter_test.dart';
import 'package:joycon_dsu/red/senal.dart';

void main() {
  test('el lector arma paquetes partidos y pegados', () {
    final a = mqttPublish('joycondsu/v1/x', 'hola' * 100); // largo de 2 bytes
    final b = mqttPublish('joycondsu/v1/y', 'chao');
    final todo = [...a, ...b];
    final l = LectorMqtt();
    expect(l.agregar(todo.sublist(0, 1)), isEmpty);
    expect(l.agregar(todo.sublist(1, 50)), isEmpty);
    final r = l.agregar(todo.sublist(50));
    expect(r.length, 2);
    expect(r[0].$1, 3);
    expect(leerPublish(r[0].$2), ('joycondsu/v1/x', 'hola' * 100));
    expect(leerPublish(r[1].$2), ('joycondsu/v1/y', 'chao'));
  });

  test('de punta a punta por el servidor MQTT real (como en el iPhone)', () async {
    final a = Senal(idAleatorio('prueba-a'));
    final b = Senal(idAleatorio('prueba-b'));
    expect(await a.conectar(), 'OPEN');
    expect(await b.conectar(), 'OPEN');
    final llego = a.mensajes.firstWhere((m) => m.tipo == 'OFFER').timeout(const Duration(seconds: 8));
    final sdp = 'v=0\r\n' * 400; // como un SDP real con varias rutas
    await b.enviar('OFFER', a.id, {'sdp': sdp, 'type': 'data'});
    final m = await llego;
    expect(m.origen, b.id);
    expect(m.datos!['sdp'], sdp);
    await a.cerrar();
    await b.cerrar();
  }, timeout: const Timeout(Duration(seconds: 40)));
}
