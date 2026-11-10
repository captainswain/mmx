import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';

import 'gpu_packet.dart';

enum RenderBackendPreference { auto, cpu, gpu }

/// Sendable across isolates. An API-backed software adapter is named explicitly;
/// successful native rendering does not imply physical GPU acceleration.
class DesktopRenderFrame {
  final Uint8List rgba;
  final String backend, diagnostic;
  final bool hardwareAccelerated;
  const DesktopRenderFrame(
    this.rgba, {
    required this.backend,
    required this.diagnostic,
    required this.hardwareAccelerated,
  });
}

/// Invoke in a worker isolate. Both auto and gpu preserve the CPU escape path;
/// gpu expresses a preference, while [NativeGpuRenderer.render] is strict.
DesktopRenderFrame renderDesktopFrame(
  List<RenderObject> objects,
  Camera camera,
  RenderOptions options, {
  RenderBackendPreference preference = RenderBackendPreference.auto,
}) {
  GpuPacket.validateFrame(options);
  if (preference != RenderBackendPreference.cpu) {
    try {
      return NativeGpuRenderer().render(objects, camera, options);
    } on Object catch (error) {
      return DesktopRenderFrame(
        Rasterizer.render(objects, camera, options),
        backend: 'CPU fallback',
        diagnostic: 'Native GPU unavailable: $error',
        hardwareAccelerated: false,
      );
    }
  }
  return DesktopRenderFrame(
    Rasterizer.render(objects, camera, options),
    backend: 'CPU',
    diagnostic: 'Software rasterizer selected',
    hardwareAccelerated: false,
  );
}

typedef _AllocateNative = Pointer<Uint8> Function(Size);
typedef _Allocate = Pointer<Uint8> Function(int);
typedef _ReleaseNative = Void Function(Pointer<Void>);
typedef _Release = void Function(Pointer<Void>);
typedef _RenderNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
);
typedef _Render = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
);

class NativeGpuRenderer {
  final DynamicLibrary library;
  late final _Allocate _allocate = library
      .lookupFunction<_AllocateNative, _Allocate>('mmx_gpu_allocate');
  late final _Release _release = library
      .lookupFunction<_ReleaseNative, _Release>('mmx_gpu_release');
  late final _Render _render = library.lookupFunction<_RenderNative, _Render>(
    'mmx_gpu_render',
  );
  late final NativeFinalizer _finalizer = NativeFinalizer(
    library.lookup<NativeFunction<_ReleaseNative>>('mmx_gpu_release'),
  );

  NativeGpuRenderer({String? libraryPath})
    : library = DynamicLibrary.open(libraryPath ?? _libraryPath()) {
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'mmx_gpu_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported GPU renderer ABI $version');
    }
  }

  static String _libraryPath() {
    final configured = Platform.environment['MMX_GPU_LIBRARY'];
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    final executable = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isLinux) {
      return '$executable/lib/libmmx_gpu.so';
    }
    if (Platform.isWindows) {
      return '$executable/mmx_gpu.dll';
    }
    if (Platform.isMacOS) {
      return '$executable/../Frameworks/libmmx_gpu.dylib';
    }
    throw UnsupportedError('Native renderer supports Linux, Windows and macOS');
  }

  DesktopRenderFrame render(
    List<RenderObject> objects,
    Camera camera,
    RenderOptions options,
  ) {
    final packet = GpuPacket.encode(objects, camera, options);
    final input = _buffer(packet.length),
        output = _buffer(options.width * options.height * 4),
        diagnostic = _buffer(4096);
    try {
      input.pointer.asTypedList(packet.length).setAll(0, packet);
      final status = _render(
        input.pointer,
        input.size,
        output.pointer,
        output.size,
        diagnostic.pointer,
        diagnostic.size,
      );
      final bytes = diagnostic.pointer.asTypedList(diagnostic.size);
      final end = bytes.indexOf(0);
      final message = utf8.decode(
        bytes.sublist(0, end < 0 ? bytes.length : end),
        allowMalformed: true,
      );
      if (status < 0) {
        throw StateError(message.isEmpty ? 'GPU rendering failed' : message);
      }
      return DesktopRenderFrame(
        Uint8List.fromList(output.pointer.asTypedList(output.size)),
        backend: status == 0 ? 'GPU (wgpu)' : 'wgpu software adapter',
        diagnostic: message,
        hardwareAccelerated: status == 0,
      );
    } finally {
      input.dispose();
      output.dispose();
      diagnostic.dispose();
    }
  }

  _NativeBuffer _buffer(int length) {
    final pointer = _allocate(length);
    if (pointer == nullptr) {
      throw StateError('GPU native allocation rejected ($length bytes)');
    }
    return _NativeBuffer(pointer, length, _release, _finalizer);
  }
}

final class _NativeBuffer implements Finalizable {
  final Pointer<Uint8> pointer;
  final int size;
  final _Release release;
  final NativeFinalizer finalizer;
  bool disposed = false;
  _NativeBuffer(this.pointer, this.size, this.release, this.finalizer) {
    finalizer.attach(this, pointer.cast(), detach: this, externalSize: size);
  }
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    finalizer.detach(this);
    release(pointer.cast());
  }
}
