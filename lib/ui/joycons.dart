// Las mitades del control con forma de Joy-Con.
import 'package:flutter/material.dart';

import '../control_app.dart';
import 'piezas.dart';

/// Carcasa de un Joy-Con: redondeada por fuera, recta por dentro.
class Carcasa extends StatelessWidget {
  const Carcasa({super.key, required this.color, required this.izquierdo, required this.child});
  final Color color;
  final bool izquierdo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const grande = Radius.circular(110);
    const chico = Radius.circular(14);
    return Container(
      decoration: BoxDecoration(
        borderRadius: izquierdo
            ? const BorderRadius.only(topLeft: grande, bottomLeft: grande, topRight: chico, bottomRight: chico)
            : const BorderRadius.only(topRight: grande, bottomRight: grande, topLeft: chico, bottomLeft: chico),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.12)!, color, Color.lerp(color, Colors.black, 0.18)!],
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 24)],
      ),
      child: child,
    );
  }
}

/// Medidas de una mitad (un Joy-Con) calculadas del espacio real de la pantalla,
/// para que todo salga lo más grande posible en cualquier celular.
class _Medidas {
  _Medidas(BoxConstraints c, {required double bordeExterior}) {
    final w = c.maxWidth, h = c.maxHeight;
    exterior = bordeExterior;
    gatillo = (h * 0.15).clamp(44.0, 64.0);
    arribaZona = 8 + gatillo + 6;
    final altoZona = h - arribaZona - 8;
    final anchoZona = w - exterior - interior;
    // Palanca y botones en diagonal: cada uno ocupa casi la mitad del ancho
    // y casi dos tercios del alto, sin chocar entre ellos.
    grande = [altoZona * 0.64, anchoZona * 0.52].reduce((a, b) => a < b ? a : b).clamp(110.0, 260.0);
    chico = (grande * 0.26).clamp(38.0, 56.0);
  }
  late final double exterior, gatillo, arribaZona, grande, chico;
  final double interior = 12;
}

/// Margen del borde de afuera: lo curvo de la carcasa y la isla o notch del iPhone.
double _bordeExterior(BuildContext context, {required bool izquierdo}) {
  final p = MediaQuery.of(context).padding;
  final notch = izquierdo ? p.left : p.right;
  return 26 + notch * 0.55;
}

/// Joy-Con izquierdo vertical (modo dos Joy-Con): palanca arriba hacia afuera,
/// cruceta abajo hacia adentro, como el de verdad.
class JoyconIzquierdo extends StatelessWidget {
  const JoyconIzquierdo({super.key, required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    final borde = _bordeExterior(context, izquierdo: true);
    return Carcasa(
      color: Color(app.colorIzq),
      izquierdo: true,
      child: LayoutBuilder(builder: (context, c) {
        final m = _Medidas(c, bordeExterior: borde);
        return Stack(children: [
          // Gatillos arriba, del lado de afuera (el centro queda para la píldora).
          Positioned(
            left: m.exterior * 0.6,
            right: 104,
            top: 8,
            child: Row(children: [
              Expanded(child: Gatillo(etiqueta: 'ZL', alto: m.gatillo, alCambiar: (v) => app.boton('ZL', v))),
              const SizedBox(width: 8),
              Expanded(child: Gatillo(etiqueta: 'L', alto: m.gatillo, alCambiar: (v) => app.boton('L', v))),
            ]),
          ),
          Positioned(
            left: m.exterior,
            top: m.arribaZona,
            child: Palanca(diametro: m.grande, alMover: (x, y) => app.palanca(izquierda: true, x: x, y: y)),
          ),
          Positioned(
            right: m.interior,
            bottom: 8,
            child: Cruz(
              tam: m.grande / 2.9,
              arriba: '↑', abajo: '↓', izq: '←', der: '→',
              iconos: true,
              alCambiar: app.boton,
            ),
          ),
          Positioned(
            right: m.interior + 4,
            top: m.arribaZona + 4,
            child: BotonJoy(etiqueta: '−', diametro: m.chico, alCambiar: (v) => app.boton('−', v)),
          ),
          Positioned(
            left: m.exterior,
            bottom: 10,
            child: Row(children: [
              BotonJoy(etiqueta: 'L3', diametro: m.chico, alCambiar: (v) => app.boton('L3', v)),
              SizedBox(width: m.chico * 0.5),
              BotonJoy(
                etiqueta: '',
                icono: Icons.circle,
                diametro: m.chico,
                forma: BoxShape.rectangle,
                colorEtiqueta: Colors.white24,
                alCambiar: (v) => app.boton('CAPT', v),
              ),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// Joy-Con derecho vertical (modo dos Joy-Con): botones arriba hacia afuera,
/// palanca abajo hacia adentro, como el de verdad.
class JoyconDerecho extends StatelessWidget {
  const JoyconDerecho({super.key, required this.app});
  final ControlApp app;

  @override
  Widget build(BuildContext context) {
    final borde = _bordeExterior(context, izquierdo: false);
    return Carcasa(
      color: Color(app.colorDer),
      izquierdo: false,
      child: LayoutBuilder(builder: (context, c) {
        final m = _Medidas(c, bordeExterior: borde);
        return Stack(children: [
          Positioned(
            left: 104,
            right: m.exterior * 0.6,
            top: 8,
            child: Row(children: [
              Expanded(child: Gatillo(etiqueta: 'R', alto: m.gatillo, alCambiar: (v) => app.boton('R', v))),
              const SizedBox(width: 8),
              Expanded(child: Gatillo(etiqueta: 'ZR', alto: m.gatillo, alCambiar: (v) => app.boton('ZR', v))),
            ]),
          ),
          Positioned(
            right: m.exterior,
            top: m.arribaZona,
            child: Cruz(tam: m.grande / 2.9, arriba: 'X', abajo: 'B', izq: 'Y', der: 'A', alCambiar: app.boton),
          ),
          Positioned(
            left: m.interior,
            bottom: 8,
            child: Palanca(diametro: m.grande, alMover: (x, y) => app.palanca(izquierda: false, x: x, y: y)),
          ),
          Positioned(
            left: m.interior + 4,
            top: m.arribaZona + 4,
            child: BotonJoy(etiqueta: '+', diametro: m.chico, alCambiar: (v) => app.boton('+', v)),
          ),
          Positioned(
            right: m.exterior,
            bottom: 10,
            child: Row(children: [
              BotonJoy(
                etiqueta: '',
                icono: Icons.home_rounded,
                diametro: m.chico,
                colorEtiqueta: Colors.white70,
                alCambiar: (v) => app.boton('HOME', v),
              ),
              SizedBox(width: m.chico * 0.5),
              BotonJoy(etiqueta: 'R3', diametro: m.chico, alCambiar: (v) => app.boton('R3', v)),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// Un solo Joy-Con acostado (como en Mario Party): palanca a un lado,
/// cuatro botones al otro y SL / SR arriba.
class JoyconDeLado extends StatelessWidget {
  const JoyconDeLado({super.key, required this.app, required this.izquierdo});
  final ControlApp app;
  final bool izquierdo;

  @override
  Widget build(BuildContext context) {
    final color = Color(izquierdo ? app.colorIzq : app.colorDer);
    return Carcasa(
      color: color,
      izquierdo: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(110),
          gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.15)!]),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final palanca = (c.maxHeight * 0.55).clamp(130.0, 220.0);
          final boton = (c.maxHeight * 0.19).clamp(52.0, 84.0);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(90, 10, 90, 0),
                child: Row(children: [
                  Expanded(child: Gatillo(etiqueta: 'SL', alCambiar: (v) => app.boton('L', v))),
                  const SizedBox(width: 24),
                  Expanded(child: Gatillo(etiqueta: 'SR', alCambiar: (v) => app.boton('R', v))),
                ]),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Palanca(
                      diametro: palanca,
                      alMover: (x, y) => app.palanca(izquierda: true, x: x, y: y),
                    ),
                    BotonJoy(
                      etiqueta: izquierdo ? '−' : '+',
                      diametro: 40,
                      alCambiar: (v) => app.boton(izquierdo ? '−' : '+', v),
                    ),
                    Cruz(tam: boton, arriba: 'X', abajo: 'B', izq: 'Y', der: 'A', alCambiar: app.boton),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Cuatro botones en cruz (ABXY o la cruceta).
class Cruz extends StatelessWidget {
  const Cruz({
    super.key,
    required this.tam,
    required this.arriba,
    required this.abajo,
    required this.izq,
    required this.der,
    required this.alCambiar,
    this.iconos = false,
  });

  final double tam;
  final String arriba, abajo, izq, der;
  final void Function(String, bool) alCambiar;
  final bool iconos;

  IconData? _icono(String s) {
    if (!iconos) return null;
    return switch (s) {
      '↑' => Icons.arrow_drop_up_rounded,
      '↓' => Icons.arrow_drop_down_rounded,
      '←' => Icons.arrow_left_rounded,
      _ => Icons.arrow_right_rounded,
    };
  }

  Widget _b(String s) => BotonJoy(
        etiqueta: s,
        icono: _icono(s),
        diametro: tam,
        alCambiar: (v) => alCambiar(s, v),
      );

  @override
  Widget build(BuildContext context) {
    final lado = tam * 2.9;
    return SizedBox(
      width: lado,
      height: lado,
      child: Stack(children: [
        Align(alignment: Alignment.topCenter, child: _b(arriba)),
        Align(alignment: Alignment.bottomCenter, child: _b(abajo)),
        Align(alignment: Alignment.centerLeft, child: _b(izq)),
        Align(alignment: Alignment.centerRight, child: _b(der)),
      ]),
    );
  }
}
