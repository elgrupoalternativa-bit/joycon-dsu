// "Saludo" inicial entre el iPhone y la central, usando el servidor público y
// gratuito de PeerJS (0.peerjs.com) solo como mensajero. Por aquí pasan los
// datos para abrir la conexión directa (SDP e ICE), no los del control.
//
// Para que los celulares se encuentren SIN escanear nada: los que están en el
// mismo Wi-Fi salen a internet con la misma IP pública, así que el nombre de la
// central se arma con esa IP. Los clientes calculan el mismo nombre y la llaman.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const _servidor = 'wss://0.peerjs.com/peerjs';

/// Nombre de la central para esta red (y una sala opcional, por si en la
/// misma red hay dos fiestas).
Future<String> nombreCentral({String sala = ''}) async {
  final ip = (await http.get(Uri.parse('https://api.ipify.org'))).body.trim();
  // FNV-1a de 32 bits: corto y suficiente para separar redes.
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
  final String tipo; // OFFER, ANSWER, CANDIDATE, OPEN, ID-TAKEN, EXPIRE, ERROR
  final String? origen;
  final Map<String, dynamic>? datos;
}

/// Conexión al mensajero. [id] es el nombre con el que nos registramos.
class Senal {
  Senal(this.id);
  final String id;

  WebSocketChannel? _ws;
  Timer? _latido;
  final _mensajes = StreamController<Mensaje>.broadcast();
  Stream<Mensaje> get mensajes => _mensajes.stream;

  /// Se conecta. Termina con OPEN (todo bien) o ID-TAKEN (ese nombre ya lo tiene
  /// otra central en esta red).
  Future<String> conectar() async {
    final token = idAleatorio('t');
    final uri = Uri.parse('$_servidor?key=peerjs&id=$id&token=$token&version=1.5.4');
    final ws = WebSocketChannel.connect(uri);
    _ws = ws;
    final primero = Completer<String>();
    ws.stream.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        final tipo = m['type'] as String? ?? '';
        if (!primero.isCompleted && (tipo == 'OPEN' || tipo == 'ID-TAKEN' || tipo == 'ERROR')) {
          primero.complete(tipo);
        }
        _mensajes.add(Mensaje(tipo, m['src'] as String?, (m['payload'] as Map?)?.cast<String, dynamic>()));
      },
      onError: (Object e) {
        if (!primero.isCompleted) primero.complete('ERROR');
      },
      onDone: () {
        if (!primero.isCompleted) primero.complete('ERROR');
        _mensajes.add(Mensaje('CLOSE', null, null));
      },
    );
    _latido = Timer.periodic(const Duration(seconds: 5), (_) {
      _ws?.sink.add(jsonEncode({'type': 'HEARTBEAT'}));
    });
    return primero.future.timeout(const Duration(seconds: 10), onTimeout: () => 'ERROR');
  }

  void enviar(String tipo, String destino, Map<String, dynamic> datos) {
    _ws?.sink.add(jsonEncode({'type': tipo, 'dst': destino, 'payload': datos}));
  }

  Future<void> cerrar() async {
    _latido?.cancel();
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
