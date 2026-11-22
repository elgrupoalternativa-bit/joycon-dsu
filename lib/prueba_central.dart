// SOLO PARA PRUEBAS: corre la clase Central real (la misma que va en el iPhone)
// dentro del navegador, para comprobar la conexión sin instalar nada.
// Se compila aparte con: flutter build web -t lib/prueba_central.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'red/conexion.dart';

class _FotosPrueba implements FuenteFotos {
  @override
  Future<List<Uint8List>> leer() async =>
      [Uint8List.fromList(List.generate(50000, (i) => i % 251)), Uint8List.fromList(List.generate(70000, (i) => i % 13))];
}

void main() {
  final reloj = Stopwatch()..start();
  late final Central central;
  final estado = ValueNotifier<String>('arrancando');
  void pintar() {
    final j = [for (var n = 1; n <= 7; n++) if (central.jugador(n) != null) 'J${n + 1}: x=${central.jugador(n)!.izqX.toStringAsFixed(2)} a=${central.jugador(n)!.a}'];
    estado.value = 'estado=${central.estado} remotos=${central.remotos} error=${central.ultimoError} ${j.join(' | ')}';
  }

  central = Central(reloj: reloj, alCambiar: pintar, fotos: _FotosPrueba());
  unawaited(central.iniciar());
  Timer.periodic(const Duration(milliseconds: 300), (_) => pintar());
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: estado,
          builder: (_, v, _) => Text(v, key: const Key('estado'), style: const TextStyle(fontSize: 18)),
        ),
      ),
    ),
  ));
}
