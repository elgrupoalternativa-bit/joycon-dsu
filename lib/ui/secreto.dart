// Easter egg: 5 toques rápidos en la franja del medio abren las fotos secretas.
// Las fotos viven solo en la central y llegan por el Wi-Fi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control_app.dart';

/// Cuenta toques: si hay [cuantos] seguidos (cada uno a menos de 700 ms del
/// anterior), abre la galería secreta.
class ToquesSecretos extends StatefulWidget {
  const ToquesSecretos({super.key, required this.app, required this.child, this.cuantos = 5});
  final ControlApp app;
  final Widget child;
  final int cuantos;

  @override
  State<ToquesSecretos> createState() => _ToquesSecretosState();
}

class _ToquesSecretosState extends State<ToquesSecretos> {
  int _n = 0;
  DateTime _ultimo = DateTime(2000);

  void _toque() {
    final ahora = DateTime.now();
    _n = ahora.difference(_ultimo).inMilliseconds < 700 ? _n + 1 : 1;
    _ultimo = ahora;
    if (_n >= widget.cuantos) {
      _n = 0;
      HapticFeedback.heavyImpact();
      abrirSecreto(context, widget.app);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toque, child: widget.child);
  }
}

void abrirSecreto(BuildContext context, ControlApp app) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: const Color(0xF2000000),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) => GaleriaSecreta(app: app),
    transitionsBuilder: (_, anim, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut, reverseCurve: Curves.easeIn),
      child: FadeTransition(opacity: anim, child: child),
    ),
  ));
}

class GaleriaSecreta extends StatefulWidget {
  const GaleriaSecreta({super.key, required this.app});
  final ControlApp app;

  @override
  State<GaleriaSecreta> createState() => _GaleriaSecretaState();
}

class _GaleriaSecretaState extends State<GaleriaSecreta> {
  final List<Uint8List> _fotos = [];
  final _pagina = PageController();
  StreamSubscription<Uint8List>? _sub;
  bool _cargando = true;
  int _actual = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _sub?.cancel();
    setState(() {
      _fotos.clear();
      _cargando = true;
    });
    _sub = widget.app.salida.fotos().listen(
      (f) => setState(() => _fotos.add(f)),
      onDone: () => setState(() => _cargando = false),
      onError: (_) => setState(() => _cargando = false),
    );
    // Si la central no contesta, no dejar la ruedita para siempre.
    Future<void>.delayed(const Duration(seconds: 25), () {
      if (mounted && _cargando && _fotos.isEmpty) setState(() => _cargando = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pagina.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    await widget.app.salida.agregarFotos();
    _cargar();
  }

  Future<void> _borrar() async {
    await widget.app.salida.borrarFoto(_actual);
    _actual = 0;
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final edita = widget.app.salida.editaFotos;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _contenido(edita)),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                child: Text(
                  _fotos.isEmpty ? '🤫 ¡Encontraste el secreto!' : '🤫 ${_actual + 1} / ${_fotos.length}${_cargando ? '…' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 8,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.white12),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          if (edita)
            Positioned(
              bottom: 8,
              right: 8,
              child: Row(children: [
                if (_fotos.isNotEmpty)
                  TextButton.icon(
                    onPressed: _borrar,
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                    label: const Text('Quitar esta', style: TextStyle(color: Colors.white70)),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE60012)),
                  onPressed: _agregar,
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text('Agregar fotos'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _contenido(bool edita) {
    if (_fotos.isEmpty) {
      if (_cargando) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Trayendo las fotos secretas…', style: TextStyle(color: Colors.white70)),
          ]),
        );
      }
      return Center(
        child: Text(
          edita
              ? 'Todavía no hay fotos secretas.\nToca «Agregar fotos» y elígelas de tu galería.'
              : 'El dueño de la consola todavía no ha puesto fotos 👀',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
        ),
      );
    }
    return PageView.builder(
      controller: _pagina,
      itemCount: _fotos.length,
      onPageChanged: (i) => setState(() => _actual = i),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 48, 12, 52),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(_fotos[i], fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}
