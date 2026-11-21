// Escoge la versión según dónde corre: app instalada o página web.
export 'nativa.dart' if (dart.library.js_interop) 'web.dart';
