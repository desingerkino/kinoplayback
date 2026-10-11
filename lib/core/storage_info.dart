import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Free space of the volume that holds [path], via libc (no plugin needed).
///
/// iOS/macOS: `statfs` (64-bit struct: u32 f_bsize @0, u64 f_bavail @24).
/// Android:   `statvfs` (LP64: u64 f_frsize @8, u64 f_bavail @32;
///                       ILP32: u32 f_frsize @4, u64 f_bavail @24).
/// Returns null if the call fails or the platform is not supported.
int? freeBytesAt(String path) {
  try {
    if (Platform.isIOS || Platform.isMacOS) return _darwin(path);
    if (Platform.isAndroid || Platform.isLinux) return _linux(path);
  } catch (_) {
    return null;
  }
  return null;
}

typedef _StatC = Int32 Function(Pointer<Utf8> path, Pointer<Uint8> buf);
typedef _StatDart = int Function(Pointer<Utf8> path, Pointer<Uint8> buf);

int? _darwin(String path) {
  final lib = DynamicLibrary.process();
  final fn = lib.lookupFunction<_StatC, _StatDart>('statfs');
  final p = path.toNativeUtf8();
  final buf = calloc<Uint8>(2176);
  try {
    if (fn(p, buf) != 0) return null;
    final bd = buf.cast<Uint32>().value; // f_bsize
    final avail = (buf + 24).cast<Uint64>().value; // f_bavail
    return bd * avail;
  } finally {
    calloc.free(p);
    calloc.free(buf);
  }
}

int? _linux(String path) {
  final lib = DynamicLibrary.process();
  final fn = lib.lookupFunction<_StatC, _StatDart>('statvfs');
  final p = path.toNativeUtf8();
  final buf = calloc<Uint8>(512);
  try {
    if (fn(p, buf) != 0) return null;
    if (sizeOf<IntPtr>() == 8) {
      final frsize = (buf + 8).cast<Uint64>().value;
      final avail = (buf + 32).cast<Uint64>().value;
      return frsize * avail;
    } else {
      final frsize = (buf + 4).cast<Uint32>().value;
      final avail = (buf + 24).cast<Uint64>().value;
      return frsize * avail;
    }
  } finally {
    calloc.free(p);
    calloc.free(buf);
  }
}

String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  if (bytes >= 100 * gb) return '${(bytes / gb).round()} GB';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1000).round()} KB';
}
