// Piezas del control: botón redondo, gatillo, palanca.
import 'dart:math';

import 'package:flutter/material.dart';

/// Botón que reacciona al toque al instante (sin esperar al "tap"),
/// y permite varios dedos a la vez.
class BotonJoy extends StatefulWidget {
  const BotonJoy({
    super.key,
    required this.etiqueta,
    required this.alCambiar,
    this.diametro = 58,
    this.colorEtiqueta = Colors.white,
    this.forma = BoxShape.circle,
    this.icono,
  });

  final String etiqueta;
  final void Function(bool presionado) alCambiar;
  final double diametro;
  final Color colorEtiqueta;
  final BoxShape forma;
  final IconData? icono;

  @override
  State<BotonJoy> createState() => _BotonJoyState();
}

class _BotonJoyState extends State<BotonJoy> {
  bool _abajo = false;

  void _poner(bool v) {
    if (v == _abajo) return;
    setState(() => _abajo = v);
    widget.alCambiar(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diametro;
    return Listener(
      onPointerDown: (_) => _poner(true),
      onPointerUp: (_) => _poner(false),
      onPointerCancel: (_) => _poner(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: d,
        height: d,
        transform: Matrix4.identity()..scaleByDouble(_abajo ? 0.9 : 1.0, _abajo ? 0.9 : 1.0, 1, 1),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: widget.forma,
          borderRadius: widget.forma == BoxShape.rectangle ? BorderRadius.circular(8) : null,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _abajo
                ? [const Color(0xFF1A1A1E), const Color(0xFF26262B)]
                : [const Color(0xFF3A3A41), const Color(0xFF1E1E22)],
          ),
          boxShadow: _abajo
              ? []
              : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(0, 3), blurRadius: 4),
                ],
        ),
        alignment: Alignment.center,
        child: widget.icono != null
            ? Icon(widget.icono, color: widget.colorEtiqueta, size: d * 0.5)
            : Text(
                widget.etiqueta,
                style: TextStyle(
                  color: widget.colorEtiqueta,
                  fontSize: d * 0.36,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

/// Gatillos L / ZL / R / ZR: barras anchas en el borde de arriba.
class Gatillo extends StatelessWidget {
  const Gatillo({super.key, required this.etiqueta, required this.alCambiar, this.ancho = 120});
  final String etiqueta;
  final void Function(bool) alCambiar;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      height: 44,
      child: BotonJoyRect(etiqueta: etiqueta, alCambiar: alCambiar),
    );
  }
}

class BotonJoyRect extends StatefulWidget {
  const BotonJoyRect({super.key, required this.etiqueta, required this.alCambiar});
  final String etiqueta;
  final void Function(bool) alCambiar;
  @override
  State<BotonJoyRect> createState() => _BotonJoyRectState();
}

class _BotonJoyRectState extends State<BotonJoyRect> {
  bool _abajo = false;
  void _poner(bool v) {
    if (v == _abajo) return;
    setState(() => _abajo = v);
    widget.alCambiar(v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _poner(true),
      onPointerUp: (_) => _poner(false),
      onPointerCancel: (_) => _poner(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        decoration: BoxDecoration(
          color: _abajo ? const Color(0xFF141417) : const Color(0xFF2B2B31),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.etiqueta,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }
}

/// Palanca analógica. Devuelve x, y entre −1 y 1 (y positivo = arriba).
/// Si la presionas fuerte (dos toques rápidos) no hace L3/R3: eso va en un botón.
class Palanca extends StatefulWidget {
  const Palanca({super.key, required this.alMover, this.diametro = 150});
  final void Function(double x, double y) alMover;
  final double diametro;

  @override
  State<Palanca> createState() => _PalancaState();
}

class _PalancaState extends State<Palanca> {
  Offset _pos = Offset.zero; // en píxeles desde el centro

  void _mover(Offset local) {
    final r = widget.diametro / 2;
    var v = local - Offset(r, r);
    final maxR = r * 0.62;
    if (v.distance > maxR) v = Offset.fromDirection(v.direction, maxR);
    setState(() => _pos = v);
    // Pantalla: y crece hacia abajo. DSU: y crece hacia arriba. Por eso el signo.
    widget.alMover(v.dx / maxR, -v.dy / maxR);
  }

  void _soltar() {
    setState(() => _pos = Offset.zero);
    widget.alMover(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diametro;
    final perilla = d * 0.46;
    return Listener(
      onPointerDown: (e) => _mover(e.localPosition),
      onPointerMove: (e) => _mover(e.localPosition),
      onPointerUp: (_) => _soltar(),
      onPointerCancel: (_) => _soltar(),
      child: SizedBox(
        width: d,
        height: d,
        child: CustomPaint(
          painter: _BasePalanca(),
          child: Center(
            child: Transform.translate(
              offset: _pos,
              child: Container(
                width: perilla,
                height: perilla,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.3),
                    colors: [Color(0xFF55555E), Color(0xFF1C1C20)],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 8, offset: const Offset(0, 4)),
                  ],
                ),
                child: CustomPaint(painter: _TexturaPerilla()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BasePalanca extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final centro = s.center(Offset.zero);
    final r = s.width / 2;
    c.drawCircle(centro, r, Paint()..color = const Color(0xFF111114));
    c.drawCircle(
      centro,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TexturaPerilla extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final centro = s.center(Offset.zero);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      c.drawCircle(centro + Offset.fromDirection(a, s.width * 0.3), 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
