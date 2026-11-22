// Conexión directa (WebRTC) entre los iPhone (página web) y la central Android.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../dsu/control_state.dart';
import 'paquete.dart';
import 'senal.dart';

typedef Aviso = void Function();

// =============================================================== CENTRAL
// Corre en el Android. Recibe hasta 7 controles remotos (jugadores 2 a 8).

/// Fotos del easter egg. Viven solo en la central y viajan por el Wi-Fi,
/// directo al celular que las pide: nunca se suben a internet.
abstract class FuenteFotos {
  Future<List<Uint8List>> leer();
}

const _tamTrozo = 16000;

class _Remoto {
  _Remoto(this.id, this.pc);
  final String id;
  final RTCPeerConnection pc;
  RTCDataChannel? canal;
  RTCDataChannel? canalFotos;
  int? jugador; // 1..7 (el 0 es el propio Android)
  final ControlState estado = ControlState();
  DateTime ultimoDato = DateTime.now();
}

class Central {
  Central({required this.reloj, required this.alCambiar, this.fotos});
  final Stopwatch reloj;
  final Aviso alCambiar;
  final FuenteFotos? fotos;

  /// Manda todas las fotos por el canal seguro: `F:i:total:bytes`,
  /// los trozos binarios, y al final `LISTO`.
  Future<void> _mandarFotos(RTCDataChannel canal) async {
    final lista = await fotos?.leer() ?? const <Uint8List>[];
    for (var i = 0; i < lista.length; i++) {
      final f = lista[i];
      await canal.send(RTCDataChannelMessage('F:$i:${lista.length}:${f.length}'));
      for (var o = 0; o < f.length; o += _tamTrozo) {
        final fin = o + _tamTrozo < f.length ? o + _tamTrozo : f.length;
        await canal.send(RTCDataChannelMessage.fromBinary(Uint8List.sublistView(f, o, fin)));
        // Sin apurar el canal: que no se llene y no le quite aire a los controles.
        await Future<void>.delayed(const Duration(milliseconds: 6));
      }
    }
    await canal.send(RTCDataChannelMessage('LISTO:${lista.length}'));
  }

  Senal? _senal;
  final Map<String, _Remoto> _remotos = {};
  Timer? _limpieza;

  /// 'buscando' | 'lista' | 'otra' (ya hay otra central en esta red) | 'error'
  String estado = 'buscando';
  int get remotos => _remotos.values.where((r) => r.jugador != null).length;

  /// Estado del jugador [n] (1..7), o null si no hay nadie ahí.
  ControlState? jugador(int n) {
    for (final r in _remotos.values) {
      if (r.jugador == n) return r.estado;
    }
    return null;
  }

  Timer? _reconexion;
  bool _detenida = false;

  /// Último error al atender a un celular (se muestra en la ayuda).
  String? ultimoError;

  Future<void> iniciar() async {
    _limpieza ??= Timer.periodic(const Duration(seconds: 2), (_) => _limpiar());
    await _registrar();
  }

  /// Se registra en el mensajero y NO se rinde: si el nombre aparece ocupado
  /// (casi siempre es nuestro propio registro viejo, de antes de reinstalar o
  /// de cuando la app quedó en segundo plano) o se cae la conexión, reintenta
  /// cada pocos segundos hasta quedar lista.
  Future<void> _registrar() async {
    _reconexion?.cancel();
    if (_detenida) return;
    final viejo = _senal;
    _senal = null; // así su aviso de "cerrado" no dispara otra reconexión
    await viejo?.cerrar();
    try {
      final nombre = await nombreCentral();
      final s = Senal(nombre);
      _senal = s;
      s.mensajes.listen((m) {
        if (m.tipo == 'CLOSE' && identical(_senal, s)) {
          estado = 'buscando';
          alCambiar();
          _reintentar(3);
          return;
        }
        _alMensaje(m);
      });
      final r = await s.conectar();
      estado = r == 'OPEN' ? 'lista' : (r == 'ID-TAKEN' ? 'otra' : 'error');
    } catch (_) {
      estado = 'error';
    }
    alCambiar();
    if (estado != 'lista') _reintentar(estado == 'otra' ? 6 : 4);
  }

  void _reintentar(int segundos) {
    _reconexion?.cancel();
    if (_detenida) return;
    _reconexion = Timer(Duration(seconds: segundos), _registrar);
  }

  /// Al volver a la app (después de bloquear el celular o cambiar de app) el
  /// mensajero suele estar caído: lo revisamos y reconectamos.
  void revisar({bool forzar = false}) {
    if (forzar || estado != 'lista') _registrar();
  }

  Future<void> detener() async {
    _detenida = true;
    _reconexion?.cancel();
    _limpieza?.cancel();
    for (final r in _remotos.values) {
      await r.pc.close();
    }
    _remotos.clear();
    await _senal?.cerrar();
  }

  void _limpiar() {
    final ahora = DateTime.now();
    final viejos = _remotos.values
        .where((r) => r.jugador != null && ahora.difference(r.ultimoDato).inSeconds > 5)
        .toList();
    for (final r in viejos) {
      r.pc.close();
      _remotos.remove(r.id);
    }
    if (viejos.isNotEmpty) alCambiar();
  }

  int? _jugadorLibre() {
    final usados = _remotos.values.map((r) => r.jugador).whereType<int>().toSet();
    for (var n = 1; n <= 7; n++) {
      if (!usados.contains(n)) return n;
    }
    return null;
  }

  Future<void> _alMensaje(Mensaje m) async {
    try {
      await _atender(m);
    } catch (e) {
      ultimoError = '$e';
      alCambiar();
    }
  }

  Future<void> _atender(Mensaje m) async {
    final origen = m.origen;
    if (origen == null || m.datos == null) return;
    final s = _senal!;

    if (m.tipo == 'OFFER') {
      final pc = await createPeerConnection(iceServers);
      final r = _Remoto(origen, pc);
      _remotos[origen]?.pc.close();
      _remotos[origen] = r;

      pc.onDataChannel = (canal) {
        if (canal.label == 'fotos') {
          r.canalFotos = canal;
          canal.onMessage = (msg) {
            if (!msg.isBinary && msg.text == 'FOTOS?') unawaited(_mandarFotos(canal));
          };
          return;
        }
        r.canal = canal;
        canal.onDataChannelState = (st) {
          if (st == RTCDataChannelState.RTCDataChannelOpen) {
            r.jugador = _jugadorLibre();
            canal.send(RTCDataChannelMessage(r.jugador == null ? 'LLENO' : 'J${r.jugador! + 1}'));
            alCambiar();
          } else if (st == RTCDataChannelState.RTCDataChannelClosed) {
            _remotos.remove(origen);
            alCambiar();
          }
        };
        canal.onMessage = (msg) {
          if (!msg.isBinary) return;
          if (decodificar(msg.binary, r.estado, reloj.elapsedMicroseconds)) {
            r.ultimoDato = DateTime.now();
          }
        };
      };

      await pc.setRemoteDescription(RTCSessionDescription(m.datos!['sdp'] as String, 'offer'));
      await pc.setLocalDescription(await pc.createAnswer());
      // Un solo mensaje con todas las rutas ya incluidas (sin goteo de candidatos).
      await s.enviar('ANSWER', origen, {'sdp': await sdpCompleto(pc), 'type': 'answer'});
    }
  }
}

/// Espera a que el celular junte sus rutas de red (ICE) y devuelve el SDP con
/// todas adentro, para mandarlo en UN solo mensaje por el mensajero.
Future<String> sdpCompleto(RTCPeerConnection pc) async {
  final listo = Completer<void>();
  pc.onIceGatheringState = (st) {
    if (st == RTCIceGatheringState.RTCIceGatheringStateComplete && !listo.isCompleted) listo.complete();
  };
  if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return (await pc.getLocalDescription())!.sdp!;
  // En la misma red las rutas locales salen al instante; no esperar de más.
  await listo.future.timeout(const Duration(milliseconds: 2500), onTimeout: () {});
  return (await pc.getLocalDescription())!.sdp!;
}

// =============================================================== CLIENTE
// Corre en la página web del iPhone. Busca la central de su red y le manda
// el estado del control 60 veces por segundo.

class Cliente {
  Cliente({required this.leer, required this.alCambiar});
  final ControlState Function() leer;
  final Aviso alCambiar;

  Senal? _senal;
  RTCPeerConnection? _pc;
  RTCDataChannel? _canal;
  RTCDataChannel? _canalFotos;
  StreamController<Uint8List>? _llegando;
  BytesBuilder? _armando;
  int _faltan = 0;
  Timer? _envio;
  Timer? _reintento;

  /// 'buscando' | 'conectando' | 'conectado' | 'sin-central' | 'lleno' | 'error'
  String estado = 'buscando';
  int? jugador;

  Future<void> iniciar() async {
    _envio = Timer.periodic(const Duration(microseconds: 16667), (_) {
      final c = _canal;
      if (c != null && c.state == RTCDataChannelState.RTCDataChannelOpen) {
        c.send(RTCDataChannelMessage.fromBinary(codificar(leer())));
      }
    });
    await _intentar();
  }

  void _poner(String e) {
    estado = e;
    alCambiar();
  }

  /// Un solo buzón por celular, para no crear "temas" nuevos en ntfy en cada
  /// intento (ntfy limita por casa: lo medimos el 21-nov-2026 con un 429).
  final String _miBuzon = idAleatorio('jugador');
  String? _central;
  int _intentos = 0;
  bool _ocupado = false;

  /// Espera entre intentos: cada vez más largo, para no gastar el cupo de la casa.
  static const _esperas = [6, 10, 20, 30, 60];

  /// Tras ~5 min sin central deja de buscar solo ('pausado'). Cualquier botón
  /// que toque el jugador la despierta.
  void despertar() {
    if (estado == 'pausado') {
      _intentos = 0;
      _intentar();
    }
  }

  void _siguiente() {
    if (estado == 'conectado') return;
    _intentos++;
    if (_intentos > 9) {
      _poner('pausado');
      return;
    }
    _reintentarEn(_esperas[(_intentos - 1).clamp(0, _esperas.length - 1)]);
  }

  /// Se conecta al buzón propio una sola vez (y otra vez solo si se cayó).
  Future<Senal?> _buzon() async {
    final actual = _senal;
    if (actual != null) return actual;
    final s = Senal(_miBuzon);
    if (await s.conectar() != 'OPEN') return null;
    _senal = s;
    s.mensajes.listen((m) async {
      if (m.tipo == 'CLOSE') {
        if (identical(_senal, s)) _senal = null;
        return;
      }
      if (m.origen != _central || m.tipo != 'ANSWER' || m.datos == null) return;
      final pc = _pc;
      if (pc == null) return;
      try {
        await pc.setRemoteDescription(RTCSessionDescription(m.datos!['sdp'] as String, 'answer'));
      } catch (_) {
        // Respuesta repetida o de un intento viejo: se ignora.
      }
    });
    return s;
  }

  Future<void> _intentar() async {
    _reintento?.cancel();
    if (_ocupado) return;
    _ocupado = true;
    try {
      _poner('buscando');
      final central = _central ??= await nombreCentral();
      final s = await _buzon();
      if (s == null) {
        _poner('error');
        _siguiente();
        return;
      }

      await _pc?.close();
      final pc = await createPeerConnection(iceServers);
      _pc = pc;
      final init = RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 0;
      final canal = await pc.createDataChannel('control', init);
      _canal = canal;
      // Canal aparte, seguro y en orden, solo para las fotos del secreto.
      final fotos = await pc.createDataChannel('fotos', RTCDataChannelInit()..ordered = true);
      _canalFotos = fotos;
      fotos.onMessage = _alTrozoFoto;

      canal.onDataChannelState = (st) {
        if (st == RTCDataChannelState.RTCDataChannelOpen) {
          _intentos = 0;
          _reintento?.cancel();
          _poner('conectado');
        } else if (st == RTCDataChannelState.RTCDataChannelClosed && identical(_canal, canal)) {
          jugador = null;
          _poner('buscando');
          _reintentarEn(2);
        }
      };
      canal.onMessage = (msg) {
        if (msg.isBinary) return;
        final t = msg.text;
        if (t == 'LLENO') {
          _poner('lleno');
        } else if (t.startsWith('J')) {
          jugador = int.tryParse(t.substring(1));
          alCambiar();
        }
      };
      pc.onConnectionState = (st) {
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed && identical(_pc, pc)) {
          _poner('error');
          _siguiente();
        }
      };

      _poner('conectando');
      await pc.setLocalDescription(await pc.createOffer());
      // Un solo mensaje con todas las rutas ya incluidas (sin goteo de candidatos).
      await s.enviar('OFFER', central, {'sdp': await sdpCompleto(pc), 'type': 'data'});

      // Si en 8 s no abrió, la central no está (o no contestó): esperar y reintentar.
      _reintento = Timer(const Duration(seconds: 8), () {
        if (estado != 'conectado') {
          _poner('sin-central');
          _siguiente();
        }
      });
    } catch (_) {
      _poner('error');
      _siguiente();
    } finally {
      _ocupado = false;
    }
  }

  void _reintentarEn(int s) {
    _reintento?.cancel();
    _reintento = Timer(Duration(seconds: s), _intentar);
  }

  /// Pide las fotos a la central. Van llegando una por una; el stream se
  /// cierra al terminar (vacío si no hay central o no hay fotos).
  Stream<Uint8List> pedirFotos() {
    _llegando?.close();
    final c = StreamController<Uint8List>();
    _llegando = c;
    final canal = _canalFotos;
    if (canal == null || canal.state != RTCDataChannelState.RTCDataChannelOpen) {
      c.close();
    } else {
      canal.send(RTCDataChannelMessage('FOTOS?'));
    }
    return c.stream;
  }

  void _alTrozoFoto(RTCDataChannelMessage msg) {
    final c = _llegando;
    if (c == null || c.isClosed) return;
    if (!msg.isBinary) {
      final t = msg.text;
      if (t.startsWith('F:')) {
        _faltan = int.tryParse(t.split(':').last) ?? 0;
        _armando = BytesBuilder(copy: false);
      } else if (t.startsWith('LISTO')) {
        c.close();
      }
      return;
    }
    final b = _armando;
    if (b == null) return;
    b.add(msg.binary);
    _faltan -= msg.binary.length;
    if (_faltan <= 0) {
      c.add(b.takeBytes());
      _armando = null;
    }
  }

  Future<void> detener() async {
    _envio?.cancel();
    _reintento?.cancel();
    await _pc?.close();
    await _senal?.cerrar();
  }
}
