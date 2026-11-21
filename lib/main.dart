import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'control_app.dart';
import 'dsu/dsu_server.dart';
import 'ui/joycons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WakelockPlus.enable(); // que la pantalla no se apague mientras juegas
  final app = ControlApp();
  await app.iniciar();
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
                const _Pantallita(),
                Expanded(child: JoyconDerecho(app: app)),
              ]),
            ModoControl.joyconIzquierdo => JoyconDeLado(app: app, izquierdo: true),
            ModoControl.joyconDerecho => JoyconDeLado(app: app, izquierdo: false),
          };
          return SafeArea(
            child: Stack(children: [
              Padding(padding: const EdgeInsets.all(6), child: control),
              Align(alignment: Alignment.topCenter, child: _Estado(app: app)),
            ]),
          );
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
      width: 46,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF050506),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
    );
  }
}

/// Píldora de arriba: IP del celular, si la Xbox está conectada y ajustes.
class _Estado extends StatelessWidget {
  const _Estado({required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    final conectado = app.emuladoresConectados > 0;
    return GestureDetector(
      onTap: () => _abrirAjustes(context, app),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: conectado ? const Color(0xFF1EDC00) : Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 10, color: conectado ? const Color(0xFF1EDC00) : Colors.orangeAccent),
          const SizedBox(width: 8),
          Text(
            app.error ?? (conectado ? 'Conectado a la Xbox' : 'Esperando la Xbox · ${app.ip}:$puertoDsu'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.settings_rounded, size: 18, color: Colors.white70),
        ]),
      ),
    );
  }
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
            _titulo('Conectar en JADYX'),
            Text(
              'En el emulador: Controles → Movimiento / DSU (cemuhook) → agrega el servidor:\n'
              '   IP: ${app.ip}     Puerto: $puertoDsu\n'
              'Celular y Xbox tienen que estar en el mismo Wi-Fi. Deja esta app abierta y la pantalla prendida.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
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
