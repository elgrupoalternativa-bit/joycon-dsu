// Versión app (APK Android / app iPhone): servidor DSU directo a la Xbox y,
// además, central para los iPhone que entran por la página web.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../dsu/control_state.dart';
import '../dsu/dsu_server.dart';
import '../red/conexion.dart';
import '../red/senal.dart' show idAleatorio;
import 'comun.dart';

const esWeb = false;

/// En la app no hay que pedir permiso de movimiento con un toque.
Future<bool> pedirPermisoMovimiento() async => true;

Stream<Movimiento> movimientos() {
  // La app va siempre horizontal con la parte de arriba a la izquierda (90°).
  final c = StreamController<Movimiento>();
  double ax = 0, ay = 0, az = 9.8;
  StreamSubscription<dynamic>? s1, s2;
  c.onListen = () {
    s1 = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      ax = e.x;
      ay = e.y;
      az = e.z;
    });
    s2 = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
      const aGrados = 57.29577951308232;
      c.add(aDsu(ax: ax, ay: ay, az: az, gx: e.x * aGrados, gy: e.y * aGrados, gz: e.z * aGrados, angulo: 90));
    });
  };
  c.onCancel = () {
    s1?.cancel();
    s2?.cancel();
  };
  return c.stream;
}

Salida crearSalida({
  required ControlState Function() leer,
  required void Function() alCambiar,
  required Stopwatch reloj,
}) =>
    _SalidaNativa(leer, alCambiar, reloj);

/// Fotos secretas guardadas dentro de la app (no en la galería ni en internet).
class _FotosLocales implements FuenteFotos {
  Future<Directory> _carpeta() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/secreto');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<File>> archivos() async {
    final d = await _carpeta();
    final l = d.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return l;
  }

  @override
  Future<List<Uint8List>> leer() async => [for (final f in await archivos()) await f.readAsBytes()];

  Future<void> agregar() async {
    // Achicadas para que viajen rápido por el Wi-Fi (~150 KB cada una).
    final elegidas = await ImagePicker().pickMultiImage(maxWidth: 1280, maxHeight: 1280, imageQuality: 72);
    final d = await _carpeta();
    for (final x in elegidas) {
      final nombre = '${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File('${d.path}/$nombre').writeAsBytes(await x.readAsBytes());
    }
  }

  Future<void> borrar(int i) async {
    final l = await archivos();
    if (i >= 0 && i < l.length) await l[i].delete();
  }
}

class _SalidaNativa implements Salida {
  _SalidaNativa(this._leer, this._alCambiar, Stopwatch reloj) {
    _central = Central(reloj: reloj, alCambiar: _alCambiar, fotos: _fotos);
    // Puerto 26760: jugador 1 (este celular) y jugadores 2 a 4 (iPhone).
    _dsu1 = DsuServer(
      puerto: puertoDsu,
      leerEstado: (r) => r == 0 ? _leer() : _central.jugador(r),
    );
    // Puerto 26761: jugadores 5 a 8.
    _dsu2 = DsuServer(puerto: puertoDsu + 1, leerEstado: (r) => _central.jugador(r + 4));
    _dsu1.conectados.addListener(_alCambiar);
    // iOS congela la conexión cuando la app sale de la pantalla. Al volver,
    // si estuvo fuera más de unos segundos, la central se registra de nuevo.
    _ciclo = AppLifecycleListener(
      onPause: () => _fuera = DateTime.now(),
      onResume: () {
        final f = _fuera;
        _central.revisar(forzar: f != null && DateTime.now().difference(f).inSeconds > 8);
        _fuera = null;
      },
    );
  }

  late final AppLifecycleListener _ciclo;
  DateTime? _fuera;

  final ControlState Function() _leer;
  final void Function() _alCambiar;
  final _FotosLocales _fotos = _FotosLocales();

  @override
  Stream<Uint8List> fotos() async* {
    for (final f in await _fotos.archivos()) {
      yield await f.readAsBytes();
    }
  }

  @override
  bool get editaFotos => true;

  @override
  void despertar() {}

  @override
  Future<void> agregarFotos() => _fotos.agregar();

  @override
  Future<void> borrarFoto(int indice) => _fotos.borrar(indice);
  late final Central _central;
  late final DsuServer _dsu1, _dsu2;
  String _ip = '…';
  String? _error;

  @override
  Future<void> iniciar() async {
    try {
      await _dsu1.iniciar();
      await _dsu2.iniciar();
    } catch (e) {
      _error = 'No se pudo abrir el puerto DSU';
    }
    _ip = await _buscarIp();
    _central.idFijo = await _idFijo();
    _alCambiar();
    // La central no bloquea: si no hay internet, el control igual funciona.
    unawaited(_central.iniciar());
  }

  @override
  Future<void> detener() async {
    _ciclo.dispose();
    await _dsu1.detener();
    await _dsu2.detener();
    await _central.detener();
  }

  @override
  bool get ok => _dsu1.conectados.value > 0;

  @override
  String get texto {
    if (_error != null) return _error!;
    final iphones = _central.remotos;
    final extra = (iphones > 0 ? ' · +$iphones' : '') + (_central.estado == 'lista' ? '' : ' · sin central');
    return ok ? 'Xbox ✓$extra' : '$_ip$extra';
  }

  @override
  String get ayuda {
    final c = switch (_central.estado) {
      'lista' => 'Este celular es la CENTRAL ✓ (${_central.servidores} de 2 servidores): los amigos escanean el QR (iPhone o Android) y entran solos, cada uno como un jugador aparte.',
      'buscando' => 'Preparando la central…',
      _ => 'La central no pudo arrancar (¿hay internet?). Reintentando… Este control igual funciona.',
    } + (_central.ultimoError == null ? '' : '\n(Último error con un amigo: ${_central.ultimoError})');
    return 'En JADYX: Controles → Movimiento / DSU (cemuhook) → agrega el servidor\n'
        '   IP: $_ip   Puerto: $puertoDsu  (jugadores 1 a 4)\n'
        '   IP: $_ip   Puerto: ${puertoDsu + 1}  (jugadores 5 a 8)\n'
        'Después, en cada Jugador de JADYX elige su control DSU: este celular es el 1º '
        'del primer servidor y los amigos llegan en orden (2º, 3º, 4º, y luego el segundo servidor).\n\n$c\n\n'
        'Celulares y Xbox en el mismo Wi-Fi. Deja la app abierta.';
  }

  /// Nombre propio de esta central, guardado en la app: el mismo siempre, así
  /// el QR impreso o guardado sigue sirviendo.
  Future<String?> _idFijo() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final f = File('${base.path}/central.txt');
      if (await f.exists()) {
        final t = (await f.readAsString()).trim();
        if (RegExp(r'^joycondsu-[a-z0-9]{10}$').hasMatch(t)) return t;
      }
      final nuevo = idAleatorio('joycondsu');
      await f.writeAsString(nuevo);
      return nuevo;
    } catch (_) {
      return null;
    }
  }

  @override
  String get linkAmigos {
    final id = _central.idFijo;
    return id == null ? linkPagina : '$linkPagina?c=$id';
  }

  Future<String> _buscarIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final nombre in ['wlan0', 'en0']) {
        for (final i in interfaces) {
          if (i.name == nombre && i.addresses.isNotEmpty) return i.addresses.first.address;
        }
      }
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && (a.address.startsWith('192.168.') || a.address.startsWith('10.'))) {
            return a.address;
          }
        }
      }
    } catch (_) {}
    return 'sin Wi-Fi';
  }
}
