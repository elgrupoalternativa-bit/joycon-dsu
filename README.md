# Joy-Con DSU

Convierte un celular en un Joy-Con con **control de movimiento** (giroscopio y acelerómetro) para el emulador de Nintendo Switch **JADYX** en Xbox, o cualquier emulador con soporte DSU / cemuhook (Eden, yuzu, Ryujinx, Cemu, Dolphin).

Cada celular es su propio servidor DSU en el puerto **26760**. Puedes conectar varios celulares, uno por jugador.

## Qué trae
- Dos Joy-Con juntos, o uno solo de lado (como en Mario Party).
- Colores de Joy-Con: rojo neón, azul neón, amarillo, verde, rosado, morado y gris.
- Botones en la posición de Switch: A a la derecha, B abajo, X arriba e Y a la izquierda, más L, R, ZL, ZR, +, −, Home y Captura.
- Eje vertical de las palancas correcto (arriba es arriba), con opción de voltearlo.
- Movimiento con sensibilidad ajustable y ejes que se pueden voltear.

## Instalar en iPhone (gratis)
1. Instala **SideStore** en el iPhone (con iOS 27 o más nuevo no necesita computador): https://sidestore.io
2. Descarga la última versión: `releases/latest/download/JoyconDSU.ipa` de este repositorio.
3. Ábrela con SideStore. Se renueva cada 7 días desde el mismo celular.

## Conectar en JADYX
Controles → Movimiento / DSU (cemuhook) → agrega un servidor con la IP que muestra la app y el puerto 26760. El celular y la Xbox tienen que estar en el mismo Wi-Fi.
