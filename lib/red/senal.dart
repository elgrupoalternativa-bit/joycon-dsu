// "Saludo" inicial entre los celulares de los amigos y la central. Por aquí
// pasan solo los datos para abrir la conexión directa (SDP con sus rutas ICE),
// no los del control: esos van directo por el Wi-Fi.
//
// Para que los celulares se encuentren SIN escanear nada: los que están en el
// mismo Wi-Fi salen a internet con la misma IP pública, así que el nombre de la
// central se arma con esa IP. Los clientes calculan el mismo nombre y la llaman.
//
// Historia del mensajero (21-nov-2026, todo medido):
// - PeerJS (0.peerjs.com) dejó de reenviar mensajes: 0 de 3 llegaron.
// - ntfy.sh funcionaba, pero limita POR CASA (IP pública): ~250 mensajes cada
//   12 h y un tope de "temas nuevos" que nos devolvió 429. En una fiesta todos
//   comparten la misma IP: muy frágil.
// - MQTT público (EMQX, HiveMQ, Mosquitto) entrega en 0,17–0,3 s y no tiene
//   ese tope. Es lo que usamos ahora, con un cliente MQTT 3.1.1 mínimo sobre
//   WebSocket (sirve igual en la app y en la página).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// En este orden: la app y la página prueban el mismo, así coinciden.
const servidoresMqtt = [
  'wss://broker.emqx.io:8084/mqtt',
  'wss://broker.hivemq.com:8884/mqtt',
];

/// Nombre de la central para esta red (y una sala opcional, por si en la
/// misma red hay dos fiestas).
Future<String> nombreCentral({String sala = ''}) async {
  final ip = (await http.get(Uri.parse('https://api.ipify.org'))).body.trim();
  return 'joycondsu-${fnv1a32('joycon-dsu|$ip|$sala').toRadixString(36)}';
}

/// FNV-1a de 32 bits que da EXACTAMENTE lo mismo en la app y en la página web.
/// Ojo: en la web los enteros son números de JavaScript y `h * 0x01000193`
/// pasa de 2^53 y pierde precisión: la página calculaba otro nombre y nunca
/// encontraba a la central (21-nov-2026). Por eso se multiplica por partes:
/// 0x01000193 = 2^24 + 0x193, y módulo 2^32 solo importa el byte bajo de h
/// en la parte de 2^24.
int fnv1a32(String texto) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(texto)) {
    h = (h ^ c) & 0xffffffff;
    h = ((((h & 0xff) << 24) & 0xffffffff) + h * 0x193) % 0x100000000;
  }
  return h;
}

String idAleatorio(String prefijo) {
  final r = Random();
  return '$prefijo-${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
}

class Mensaje {
  Mensaje(this.tipo, this.origen, this.datos);
  final String tipo; // OFFER, ANSWER, CLOSE
  final String? origen;
  final Map<String, dynamic>? datos;
}

String _tema(String id) => 'joycondsu/v1/$id';

// ------------------------------------------------------------- MQTT mínimo
// Solo lo que necesitamos: CONNECT, SUBSCRIBE, PUBLISH (QoS 0) y PINGREQ.

List<int> _largo(int n) {
  final b = <int>[];
  do {
    var d = n % 128;
    n ~/= 128;
    if (n > 0) d |= 128;
    b.add(d);
  } while (n > 0);
  return b;
}

List<int> _texto(String s) {
  final e = utf8.encode(s);
  return [e.length >> 8, e.length & 255, ...e];
}

Uint8List _paquete(int tipo, List<int> cuerpo) => Uint8List.fromList([tipo, ..._largo(cuerpo.length), ...cuerpo]);

Uint8List mqttConnect(String clientId) =>
    _paquete(0x10, [..._texto('MQTT'), 4, 2, 0, 60, ..._texto(clientId)]); // MQTT 3.1.1, sesión limpia, keepalive 60 s

Uint8List mqttSubscribe(String tema) => _paquete(0x82, [0, 1, ..._texto(tema), 0]);

Uint8List mqttPublish(String tema, String texto) => _paquete(0x30, [..._texto(tema), ...utf8.encode(texto)]);

/// Junta los pedazos que llegan por el WebSocket y saca paquetes MQTT
/// completos (pueden venir varios juntos o uno partido).
class LectorMqtt {
  final _buf = <int>[];

  /// Devuelve (tipo, cuerpo) de cada paquete completo.
  List<(int, Uint8List)> agregar(List<int> datos) {
    _buf.addAll(datos);
    final salida = <(int, Uint8List)>[];
    while (_buf.length >= 2) {
      var i = 1, mult = 1, n = 0, d = 0;
      do {
        if (i >= _buf.length) return salida; // falta el largo completo
        d = _buf[i++];
        n += (d & 127) * mult;
        mult *= 128;
      } while (d & 128 != 0);
      if (_buf.length < i + n) return salida; // falta el cuerpo
      salida.add((_buf[0] >> 4, Uint8List.fromList(_buf.sublist(i, i + n))));
      _buf.removeRange(0, i + n);
    }
    return salida;
  }
}

/// Saca tema y texto de un PUBLISH QoS 0.
(String, String) leerPublish(Uint8List cuerpo) {
  final largoTema = (cuerpo[0] << 8) | cuerpo[1];
  final tema = utf8.decode(cuerpo.sublist(2, 2 + largoTema));
  return (tema, utf8.decode(cuerpo.sublist(2 + largoTema), allowMalformed: true));
}

// ----------------------------------------------------------------- Senal

/// Conexión al mensajero. [id] es nuestro "buzón": lo que otros publiquen ahí
/// nos llega.
class Senal {
  Senal(this.id);
  final String id;

  WebSocketChannel? _ws;
  Timer? _ping;
  bool _cerrada = false;
  final _mensajes = StreamController<Mensaje>.broadcast();
  Stream<Mensaje> get mensajes => _mensajes.stream;

  /// Se conecta al primer servidor que responda y se suscribe al buzón.
  /// Termina con OPEN o ERROR.
  Future<String> conectar() async {
    for (final url in servidoresMqtt) {
      if (await _probar(url)) return 'OPEN';
    }
    return 'ERROR';
  }

  Future<bool> _probar(String url) async {
    WebSocketChannel ws;
    try {
      ws = WebSocketChannel.connect(Uri.parse(url), protocols: ['mqtt']);
      await ws.ready.timeout(const Duration(seconds: 6));
    } catch (_) {
      return false;
    }
    final lector = LectorMqtt();
    final aceptado = Completer<bool>();
    ws.stream.listen(
      (raw) {
        final datos = raw is String ? utf8.encode(raw) : (raw is ByteBuffer ? raw.asUint8List() : raw as List<int>);
        for (final (tipo, cuerpo) in lector.agregar(datos)) {
          if (tipo == 2) {
            // CONNACK: el segundo byte es el código (0 = aceptado).
            if (!aceptado.isCompleted) aceptado.complete(cuerpo.length >= 2 && cuerpo[1] == 0);
          } else if (tipo == 3) {
            final (_, texto) = leerPublish(cuerpo);
            try {
              final c = jsonDecode(texto) as Map<String, dynamic>;
              if (c['de'] == id) continue; // el eco de lo nuestro
              _mensajes.add(Mensaje(c['tipo'] as String? ?? '', c['de'] as String?, (c['datos'] as Map?)?.cast<String, dynamic>()));
            } catch (_) {
              // Algo que no es nuestro en el tema: se ignora.
            }
          }
        }
      },
      onError: (Object e) {
        if (!aceptado.isCompleted) aceptado.complete(false);
      },
      onDone: () {
        if (!aceptado.isCompleted) aceptado.complete(false);
        if (identical(_ws, ws) && !_cerrada) _mensajes.add(Mensaje('CLOSE', null, null));
      },
    );
    final r = Random();
    ws.sink.add(mqttConnect('jc${List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join()}'));
    final ok = await aceptado.future.timeout(const Duration(seconds: 6), onTimeout: () => false);
    if (!ok) {
      await ws.sink.close();
      return false;
    }
    _ws = ws;
    ws.sink.add(mqttSubscribe(_tema(id)));
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 30), (_) => _ws?.sink.add(Uint8List.fromList([0xC0, 0])));
    // Dar un respiro para que la suscripción quede activa antes de que nos escriban.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return true;
  }

  /// Publica un mensaje en el buzón de [destino].
  Future<void> enviar(String tipo, String destino, Map<String, dynamic> datos) async {
    _ws?.sink.add(mqttPublish(_tema(destino), jsonEncode({'tipo': tipo, 'de': id, 'datos': datos})));
  }

  Future<void> cerrar() async {
    _cerrada = true;
    _ping?.cancel();
    await _ws?.sink.close();
  }
}

/// Servidores STUN públicos, por si la conexión directa por la red local falla.
const iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ],
};
