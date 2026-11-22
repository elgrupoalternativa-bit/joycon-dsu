import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'control_app.dart';
import 'ui/joycons.dart';
import 'ui/secreto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = ControlApp();
  if (!ControlApp.esWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // que la pantalla no se apague mientras juegas
    unawaited(app.arrancar());
  }
  runApp(JoyconDsuApp(app: app));
}

class JoyconDsuApp extends StatelessWidget {
  const JoyconDsuApp({super.key, required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Joy-Con DSU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE60012), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        fontFamily: 'Roboto',
      ),
      home: PantallaControl(app: app),
    );
  }
}

class PantallaControl extends StatelessWidget {
  const PantallaControl({super.key, required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final control = switch (app.modo) {
            ModoControl.dosJoycon => Row(children: [
                Expanded(child: JoyconIzquierdo(app: app)),
                ToquesSecretos(app: app, child: const _Pantallita()),
                Expanded(child: JoyconDerecho(app: app)),
              ]),
            ModoControl.joyconIzquierdo => JoyconDeLado(app: app, izquierdo: true),
            ModoControl.joyconDerecho => JoyconDeLado(app: app, izquierdo: false),
          };
          final vertical = MediaQuery.of(context).orientation == Orientation.portrait;
          // El control va de borde a borde (las carcasas ya dejan margen para la
          // isla o el notch); solo los avisos respetan el área segura.
          return Stack(children: [
            Padding(padding: const EdgeInsets.all(4), child: control),
            // Con un solo Joy-Con no hay franja: el secreto queda en la esquina de abajo a la izquierda.
            if (app.modo != ModoControl.dosJoycon)
              Positioned(
                left: 0,
                bottom: 0,
                child: ToquesSecretos(app: app, child: const SizedBox(width: 60, height: 60)),
              ),
            SafeArea(child: Align(alignment: Alignment.topCenter, child: _Estado(app: app))),
            if (!app.arrancado) SafeArea(child: _Empezar(app: app)),
            if (app.arrancado && vertical && ControlApp.esWeb) const SafeArea(child: _Gira()),
          ]);
        },
      ),
    );
  }
}

/// La franja negra del medio, como la pantalla del Switch.
class _Pantallita extends StatelessWidget {
  const _Pantallita();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF050506),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
    );
  }
}

/// Pantalla inicial de la página web: Safari exige un toque para dar permiso
/// al giroscopio.
class _Empezar extends StatelessWidget {
  const _Empezar({required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF20E0E10),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 34, height: 70, decoration: BoxDecoration(color: Color(app.colorIzq), borderRadius: const BorderRadius.horizontal(left: Radius.circular(30), right: Radius.circular(6)))),
          const SizedBox(width: 6),
          Container(width: 34, height: 70, decoration: BoxDecoration(color: Color(app.colorDer), borderRadius: const BorderRadius.horizontal(right: Radius.circular(30), left: Radius.circular(6)))),
        ]),
        const SizedBox(height: 18),
        const Text('Joy-Con DSU', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Tu celular como control, con movimiento', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 22),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE60012),
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          onPressed: app.arrancar,
          icon: const Icon(Icons.sports_esports_rounded),
          label: const Text('Empezar a jugar'),
        ),
        const SizedBox(height: 12),
        const Text('Te va a pedir permiso de movimiento: dale Permitir.', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
    );
  }
}

class _Gira extends StatelessWidget {
  const _Gira();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF20E0E10),
      alignment: Alignment.center,
      child: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.screen_rotation_rounded, size: 64),
        SizedBox(height: 14),
        Text('Pon el celular horizontal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Si no gira: quita el bloqueo de rotación en el Centro de control', style: TextStyle(color: Colors.white60)),
      ]),
    );
  }
}

/// Píldora de arriba: estado de la conexión y ajustes.
class _Estado extends StatelessWidget {
  const _Estado({required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    final conectado = app.salida.ok;
    return GestureDetector(
      onTap: () => _abrirAjustes(context, app),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: conectado ? const Color(0xFF1EDC00) : Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: conectado ? const Color(0xFF1EDC00) : Colors.orangeAccent),
          const SizedBox(width: 8),
          Text(app.salida.texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (app.sinMovimiento) ...[
            const SizedBox(width: 6),
            const Icon(Icons.screen_rotation_alt_rounded, size: 15, color: Colors.orangeAccent),
          ],
          if (!ControlApp.esWeb) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _mostrarQr(context),
              child: const Icon(Icons.qr_code_2_rounded, size: 20, color: Colors.white),
            ),
          ],
          const SizedBox(width: 10),
          const Icon(Icons.settings_rounded, size: 18, color: Colors.white70),
        ]),
      ),
    );
  }
}

/// Link de la página que abren los amigos (iPhone o Android, sin instalar nada).
const linkAmigos = 'https://elgrupoalternativa-bit.github.io/joycon-dsu/';

class _Qr extends StatelessWidget {
  const _Qr({this.tamano = 200});
  final double tamano;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: QrImageView(data: linkAmigos, size: tamano, backgroundColor: Colors.white),
    );
  }
}

void _mostrarQr(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xFF17171A),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(builder: (context, c) {
          final alto = MediaQuery.of(context).size.height;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            _Qr(tamano: (alto - 120).clamp(140, 260)),
            const SizedBox(width: 20),
            const SizedBox(
              width: 230,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Únete a la partida', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                SizedBox(height: 10),
                Text('1. Conéctate a este mismo Wi-Fi.\n'
                    '2. Escanea con la cámara.\n'
                    '3. Toca «Empezar a jugar» y pon el celular horizontal.\n\n'
                    'Cada celular entra como un jugador aparte.',
                    style: TextStyle(color: Colors.white70, height: 1.4)),
              ]),
            ),
          ]);
        }),
      ),
    ),
  );
}

void _abrirAjustes(BuildContext context, ControlApp app) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF17171A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => ListenableBuilder(
      listenable: app,
      builder: (context, _) => _Ajustes(app: app),
    ),
  );
}

class _Ajustes extends StatelessWidget {
  const _Ajustes({required this.app});
  final ControlApp app;

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _colores({required bool izquierdo}) {
    final actual = izquierdo ? app.colorIzq : app.colorDer;
    return Wrap(
      spacing: 10,
      children: [
        for (final c in coloresJoycon)
          GestureDetector(
            onTap: () => app.cambiarColor(izquierdo: izquierdo, color: c.valor),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(c.valor),
                shape: BoxShape.circle,
                border: Border.all(color: actual == c.valor ? Colors.white : Colors.transparent, width: 3),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = app.movimiento;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            _titulo(ControlApp.esWeb ? 'Cómo funciona' : 'Conectar en JADYX'),
            Text(app.salida.ayuda, style: const TextStyle(color: Colors.white70, height: 1.4)),
            if (!ControlApp.esWeb) ...[
              _titulo('QR para tus amigos'),
              const Align(alignment: Alignment.centerLeft, child: _Qr(tamano: 170)),
            ],
            _titulo('Cómo quieres el control'),
            SegmentedButton<ModoControl>(
              segments: const [
                ButtonSegment(value: ModoControl.dosJoycon, label: Text('Dos Joy-Con')),
                ButtonSegment(value: ModoControl.joyconIzquierdo, label: Text('Solo izquierdo')),
                ButtonSegment(value: ModoControl.joyconDerecho, label: Text('Solo derecho')),
              ],
              selected: {app.modo},
              onSelectionChanged: (s) => app.cambiarModo(s.first),
            ),
            _titulo('Color del Joy-Con izquierdo'),
            _colores(izquierdo: true),
            _titulo('Color del Joy-Con derecho'),
            _colores(izquierdo: false),
            _titulo('Movimiento'),
            Row(children: [
              const Text('Sensibilidad'),
              Expanded(
                child: Slider(
                  value: m.sensibilidad,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: m.sensibilidad.toStringAsFixed(1),
                  onChanged: (v) {
                    m.sensibilidad = v;
                    app.avisar();
                  },
                ),
              ),
            ]),
            SwitchListTile(
              title: const Text('Voltear inclinación adelante/atrás'),
              value: m.invertirPitch,
              onChanged: (v) {
                m.invertirPitch = v;
                app.avisar();
              },
            ),
            SwitchListTile(
              title: const Text('Voltear giro izquierda/derecha'),
              value: m.invertirYaw,
              onChanged: (v) {
                m.invertirYaw = v;
                app.avisar();
              },
            ),
            SwitchListTile(
              title: const Text('Voltear giro de lado (volante)'),
              value: m.invertirRoll,
              onChanged: (v) {
                m.invertirRoll = v;
                app.avisar();
              },
            ),
            SwitchListTile(
              title: const Text('Voltear eje vertical de las palancas'),
              subtitle: const Text('Solo si arriba se mueve hacia abajo en el juego'),
              value: m.invertirPalancaY,
              onChanged: (v) {
                m.invertirPalancaY = v;
                app.avisar();
              },
            ),
          ],
        ),
      ),
    );
  }
}
