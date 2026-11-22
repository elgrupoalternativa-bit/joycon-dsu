// Versión página web (para iPhone sin instalar nada): lee el movimiento del
// navegador y se lo manda a la central Android de la misma red.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../dsu/control_state.dart';
import '../red/conexion.dart';
import 'comun.dart';

const esWeb = true;

bool get _esIOS {
  final ua = web.window.navigator.userAgent;
  return ua.contains('iPhone') || ua.contains('iPad') || (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
}

/// En iPhone, Safari solo entrega el giroscopio después de pedir permiso con
/// un toque. Hay que llamarla desde el toque de un botón.
Future<bool> pedirPermisoMovimiento() async {
  final dme = web.window.getProperty<JSObject?>('DeviceMotionEvent'.toJS);
  if (dme == null) return false;
  if (!dme.has('requestPermission')) return true; // Android / navegadores viejos
  try {
    final r = await dme.callMethod<JSPromise<JSString>>('requestPermission'.toJS).toDart;
    return r.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

int _anguloPantalla() {
  try {
    return web.window.screen.orientation.angle;
  } catch (_) {
    return 0;
  }
}

Stream<Movimiento> movimientos() {
  final c = StreamController<Movimiento>();
  // iPhone: la gravedad viene con el signo al revés que en Android.
  final signo = _esIOS ? -1.0 : 1.0;
  JSFunction? oyente;
  c.onListen = () {
    oyente = ((web.DeviceMotionEvent e) {
      final a = e.accelerationIncludingGravity;
      final r = e.rotationRate;
      if (a == null || r == null) return;
      var ang = _anguloPantalla();
      if (ang > 180) ang -= 360;
      c.add(aDsu(
        ax: (a.x ?? 0) * signo,
        ay: (a.y ?? 0) * signo,
        az: (a.z ?? 0) * signo,
        gx: r.beta ?? 0, // giro alrededor de X, en °/s
        gy: r.gamma ?? 0, // alrededor de Y
        gz: r.alpha ?? 0, // alrededor de Z
        angulo: ang,
      ));
    }).toJS;
    web.window.addEventListener('devicemotion', oyente);
  };
  c.onCancel = () {
    if (oyente != null) web.window.removeEventListener('devicemotion', oyente);
  };
  return c.stream;
}

Salida crearSalida({
  required ControlState Function() leer,
  required void Function() alCambiar,
  required Stopwatch reloj,
}) =>
    _SalidaWeb(leer, alCambiar);

class _SalidaWeb implements Salida {
  _SalidaWeb(ControlState Function() leer, void Function() alCambiar) {
    final c = Uri.base.queryParameters['c'];
    _cliente = Cliente(
      leer: leer,
      alCambiar: alCambiar,
      // Solo nombres nuestros: letras, números y guiones.
      centralDelQr: c != null && RegExp(r'^joycondsu-[a-z0-9-]{4,40}$').hasMatch(c) ? c : null,
    );
  }

  late final Cliente _cliente;

  @override
  Future<void> iniciar() => _cliente.iniciar();

  @override
  Future<void> detener() => _cliente.detener();

  @override
  bool get ok => _cliente.estado == 'conectado';

  @override
  Stream<Uint8List> fotos() => _cliente.pedirFotos();

  @override
  void despertar() => _cliente.despertar();

  @override
  bool get editaFotos => false;

  @override
  String get linkAmigos => linkPagina;

  @override
  Future<void> agregarFotos() async {}

  @override
  Future<void> borrarFoto(int indice) async {}

  @override
  String get texto => switch (_cliente.estado) {
        'conectado' => _cliente.jugador != null ? 'Jugador ${_cliente.jugador}' : 'Conectado',
        'conectando' => 'Conectando…',
        'sin-central' => 'Sin central',
        'sin-enlace' => 'Sin enlace · reintento',
        'lleno' => 'Ya hay 8',
        'error' => 'Reintentando…',
        'pausado' => 'Sin central · toca un botón',
        _ => 'Buscando…',
      };

  @override
  String get ayuda =>
      'Estado: ${switch (_cliente.estado) {
        'conectado' => 'conectado a la central${_cliente.jugador != null ? ' como jugador ${_cliente.jugador}' : ''}.',
        'sin-central' => 'la central no contesta. ¿El celular del dueño tiene la app abierta y en pantalla?',
        'sin-enlace' => 'la central contestó, pero el enlace directo por el Wi-Fi no abrió. Revisa que estés en el mismo Wi-Fi (no en datos).',
        'lleno' => 'la central ya tiene 8 jugadores.',
        'error' => 'error: ${_cliente.detalle ?? 'desconocido'}.',
        _ => 'buscando la central…',
      }}\n'
      '(Central: ${_cliente.central ?? '…'}${_cliente.centralDelQr != null ? ', del QR' : ', por la red'})\n\n'
      'Este control funciona por el link, sin instalar nada.\n\n'
      'Necesita que en el mismo Wi-Fi esté la central: el celular del dueño de la consola '
      'con la app Joy-Con DSU abierta. Ella le pasa tu control a la Xbox como un jugador '
      'aparte. Te conectas solo.\n\n'
      'Pon el celular horizontal y deja esta página abierta mientras juegas.';
}
