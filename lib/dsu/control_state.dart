// Todo lo que el control le manda al emulador en un instante.
class ControlState {
  // Botones de Switch.
  bool a = false, b = false, x = false, y = false;
  bool l = false, r = false, zl = false, zr = false;
  bool mas = false, menos = false, home = false, captura = false;
  bool l3 = false, r3 = false;
  bool arriba = false, abajo = false, izquierda = false, derecha = false;

  // Palancas, de -1 a 1. Y positivo = arriba.
  double izqX = 0, izqY = 0, derX = 0, derY = 0;

  // Movimiento ya convertido a la convención DSU.
  int tiempoMicros = 0;
  double accelX = 0, accelY = 0, accelZ = 0; // en g
  double gyroPitch = 0, gyroYaw = 0, gyroRoll = 0; // en grados por segundo
}
