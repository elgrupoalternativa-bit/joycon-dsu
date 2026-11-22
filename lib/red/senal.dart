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

// Antes usábamos el servidor público de PeerJS, pero dejó de reenviar los
// mensajes (medido el 21-nov-2026: 0 de 3 llegaron). Ahora el mensajero es
// ntfy.sh: gratis, sin cuenta; cada celular escucha su "tema" por WebSocket y
// los demás le publican con un POST. Solo pasa el saludo (SDP); el control va
// directo por el Wi-Fi.
const _ntfy = 'ntfy.sh';

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

/// Conexión al mensajero. [id] es nuestro "buzón": lo que otros publiquen ahí
/// nos llega.
class Senal {
  Senal(this.id);
  final String id;

  WebSocketChannel? _ws;
  final _mensajes = StreamController<Mensaje>.broadcast();
  Stream<Mensaje> get mensajes => _mensajes.stream;

  /// Se conecta. Termina con OPEN (escuchando) o ERROR.
  Future<String> conectar() async {
    final ws = WebSocketChannel.connect(Uri.parse('wss://$_ntfy/$id/ws'));
    _ws = ws;
    final primero = Completer<String>();
    ws.stream.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        final evento = m['event'] as String? ?? '';
        if (evento == 'open') {
          if (!primero.isCompleted) primero.complete('OPEN');
          return;
        }
        if (evento != 'message') return; // keepalive, etc.
        try {
          final c = jsonDecode(m['message'] as String) as Map<String, dynamic>;
          _mensajes.add(Mensaje(
            c['tipo'] as String? ?? '',
            c['de'] as String?,
            (c['datos'] as Map?)?.cast<String, dynamic>(),
          ));
        } catch (_) {
          // Algo que no es nuestro en el tema: se ignora.
        }
      },
      onError: (Object e) {
        if (!primero.isCompleted) primero.complete('ERROR');
      },
      onDone: () {
        if (!primero.isCompleted) primero.complete('ERROR');
        _mensajes.add(Mensaje('CLOSE', null, null));
      },
    );
    return primero.future.timeout(const Duration(seconds: 10), onTimeout: () => 'ERROR');
  }

  /// Publica un mensaje en el buzón de [destino].
  Future<void> enviar(String tipo, String destino, Map<String, dynamic> datos) async {
    await http.post(
      Uri.parse('https://$_ntfy/$destino'),
      body: jsonEncode({'tipo': tipo, 'de': id, 'datos': datos}),
    );
  }

  Future<void> cerrar() async {
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
