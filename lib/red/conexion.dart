// Conexión directa (WebRTC) entre los iPhone (página web) y la central Android.
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../dsu/control_state.dart';
import 'paquete.dart';
import 'senal.dart';

typedef Aviso = void Function();

// =============================================================== CENTRAL
// Corre en el Android. Recibe hasta 7 controles remotos (jugadores 2 a 8).

class _Remoto {
  _Remoto(this.id, this.pc);
  final String id;
  final RTCPeerConnection pc;
  RTCDataChannel? canal;
  int? jugador; // 1..7 (el 0 es el propio Android)
  final ControlState estado = ControlState();
  DateTime ultimoDato = DateTime.now();
}

class Central {
  Central({required this.reloj, required this.alCambiar});
  final Stopwatch reloj;
  final Aviso alCambiar;

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

  Future<void> iniciar() async {
    try {
      final nombre = await nombreCentral();
      final s = Senal(nombre);
      _senal = s;
      s.mensajes.listen(_alMensaje);
      final r = await s.conectar();
      estado = r == 'OPEN' ? 'lista' : (r == 'ID-TAKEN' ? 'otra' : 'error');
    } catch (_) {
      estado = 'error';
    }
    _limpieza = Timer.periodic(const Duration(seconds: 2), (_) => _limpiar());
    alCambiar();
  }

  Future<void> detener() async {
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
    final origen = m.origen;
    if (origen == null || m.datos == null) return;
    final s = _senal!;

    if (m.tipo == 'OFFER') {
      final pc = await createPeerConnection(iceServers);
      final r = _Remoto(origen, pc);
      _remotos[origen]?.pc.close();
      _remotos[origen] = r;

      pc.onIceCandidate = (c) {
        if (c.candidate == null) return;
        s.enviar('CANDIDATE', origen, {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };
      pc.onDataChannel = (canal) {
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
      final respuesta = await pc.createAnswer();
      await pc.setLocalDescription(respuesta);
      s.enviar('ANSWER', origen, {'sdp': respuesta.sdp, 'type': 'answer'});
    } else if (m.tipo == 'CANDIDATE') {
      final r = _remotos[origen];
      if (r == null) return;
      await r.pc.addCandidate(RTCIceCandidate(
        m.datos!['candidate'] as String?,
        m.datos!['sdpMid'] as String?,
        (m.datos!['sdpMLineIndex'] as num?)?.toInt(),
      ));
    }
  }
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

  Future<void> _intentar() async {
    _reintento?.cancel();
    try {
      _poner('buscando');
      final central = await nombreCentral();
      await _senal?.cerrar();
      final s = Senal(idAleatorio('jugador'));
      _senal = s;
      if (await s.conectar() != 'OPEN') {
        _poner('error');
        _reintentarEn(4);
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

      canal.onDataChannelState = (st) {
        if (st == RTCDataChannelState.RTCDataChannelOpen) {
          _poner('conectado');
        } else if (st == RTCDataChannelState.RTCDataChannelClosed) {
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
      pc.onIceCandidate = (c) {
        if (c.candidate == null) return;
        s.enviar('CANDIDATE', central, {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };
      pc.onConnectionState = (st) {
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _poner('error');
          _reintentarEn(3);
        }
      };

      s.mensajes.listen((m) async {
        if (m.origen != central) return;
        if (m.tipo == 'ANSWER' && m.datos != null) {
          await pc.setRemoteDescription(RTCSessionDescription(m.datos!['sdp'] as String, 'answer'));
        } else if (m.tipo == 'CANDIDATE' && m.datos != null) {
          await pc.addCandidate(RTCIceCandidate(
            m.datos!['candidate'] as String?,
            m.datos!['sdpMid'] as String?,
            (m.datos!['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } else if (m.tipo == 'EXPIRE') {
          // La central no está prendida en esta red.
          _poner('sin-central');
          _reintentarEn(4);
        }
      });

      _poner('conectando');
      final oferta = await pc.createOffer();
      await pc.setLocalDescription(oferta);
      s.enviar('OFFER', central, {'sdp': oferta.sdp, 'type': 'data'});

      // Si en 12 s no abrió, volver a intentar.
      _reintento = Timer(const Duration(seconds: 12), () {
        if (estado != 'conectado') {
          _poner('sin-central');
          _intentar();
        }
      });
    } catch (_) {
      _poner('error');
      _reintentarEn(4);
    }
  }

  void _reintentarEn(int s) {
    _reintento?.cancel();
    _reintento = Timer(Duration(seconds: s), _intentar);
  }

  Future<void> detener() async {
    _envio?.cancel();
    _reintento?.cancel();
    await _pc?.close();
    await _senal?.cerrar();
  }
}
