//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift System open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift System project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if os(Windows)

import WinSDK

// Shared machinery for the `GetFileInformationByHandleEx` information classes
// whose C structs are a fixed header followed by a flexible array member, and
// which therefore cannot be modelled as a `FileInfoByHandle` type:
//
//   * `FileNameInfo` / `FileNormalizedNameInfo` — one variable-length record.
//   * `FileStreamInfo` — a chain of variable-length records, all in one call.
//   * the directory-enumeration classes — a chain of variable-length records,
//     delivered a batch at a time from a cursor held by the kernel.
//
// Two hazards are common to all of them, and both are handled here rather than
// by each caller:
//
//   1. The buffer size is discovered, not known. Windows answers a short buffer
//      with `ERROR_MORE_DATA` and, for most classes, no indication of how much
//      room it actually needs.
//   2. Every length and offset in the result — `FileNameLength`,
//      `NextEntryOffset` — is a number chosen by the file system. Used
//      unchecked to bound a read or advance a pointer, any of them is an
//      out-of-bounds access.

/// The number of UTF-16 code units in the longest path Windows will produce.
///
/// A request for more than this is a misbehaving file system rather than a
/// buffer that needs growing, so it bounds the retry loop in ``_fileName``.
@available(System 99, *)
internal var _maximumWidePathLength: Int { 32767 }

/// A raw Win32 error code, wrapped so it can travel in a `Result`.
///
/// The code is deliberately left unmapped. Several information classes signal a
/// normal end of results with an error code that maps to the same ``Errno`` as a
/// genuine failure — `ERROR_NO_MORE_FILES` becomes `ENOENT`, `ERROR_HANDLE_EOF`
/// becomes `EINVAL` — so only the caller knows which codes are terminal for the
/// class it asked for, and it needs the raw code to recognise them.
@available(System 99, *)
@usableFromInline
internal struct _Win32Error: Error {
  @usableFromInline
  internal var code: DWORD

  @usableFromInline
  internal init(_ code: DWORD) { self.code = code }
}

/// Calls `GetFileInformationByHandleEx`, growing the buffer until the result
/// fits, and passes the filled buffer to `body`.
///
/// The buffer is owned by this function: it is allocated at `alignment`,
/// zero-filled before each attempt, and valid only for the duration of `body`.
/// Zeroing matters for the chained classes — Windows reports neither how many
/// bytes it wrote nor where the chain ends, so a malformed `NextEntryOffset`
/// can at worst land on a run of zeroes, which terminates the walk, rather than
/// on stale bytes that look like another entry.
///
/// - Parameters:
///   - fd: The C runtime file descriptor to query.
///   - infoClass: The raw information class to request.
///   - initialCapacity: The size of the first attempt, in bytes.
///   - maximumCapacity: The largest buffer to grow to. Once an attempt at this
///     size still reports `ERROR_MORE_DATA`, that error is returned.
///   - alignment: The alignment the buffer is allocated at.
///   - capacityHint: Given a buffer that was too small, returns the total
///     capacity its header claims is required, or `0` if the class provides no
///     such hint. The loop takes the larger of this and a doubling, so a driver
///     that under-reports cannot stall progress.
///   - body: Receives the filled, read-only buffer.
///
/// - Returns: The value returned by `body`, or the raw Win32 error code on
///   failure, as a ``_Win32Error``.
@available(System 99, *)
@usableFromInline
internal func _withFileInformationBuffer<R>(
  fileDescriptor fd: CInt,
  infoClass: FILE_INFO_BY_HANDLE_CLASS,
  initialCapacity: Int,
  maximumCapacity: Int,
  alignment: Int,
  capacityHint: (UnsafeRawBufferPointer) -> Int,
  _ body: (UnsafeRawBufferPointer) -> R
) -> Result<R, _Win32Error> {
  // Returns the finished result, or `nil` paired with the capacity to retry at.
  // A tuple rather than a local enum: a type declared inside a generic function
  // cannot reference that function's generic parameters.
  func attempt(
    into buffer: UnsafeMutableRawBufferPointer
  ) -> (Result<R, _Win32Error>?, Int) {
    buffer.initializeMemory(as: UInt8.self, repeating: 0)

    let error = system_getFileInformationByHandleEx_error(fd, infoClass, buffer)
    let filled = UnsafeRawBufferPointer(buffer)

    if error == ERROR_MORE_DATA, buffer.count < maximumCapacity {
      let required = capacityHint(filled)
      return (nil, Swift.min(
        Swift.max(required, buffer.count * 2), maximumCapacity))
    }
    // A short buffer at `maximumCapacity` falls through to here, surfacing
    // `ERROR_MORE_DATA` rather than looping.
    guard error == ERROR_SUCCESS else {
      return (.failure(_Win32Error(error)), 0)
    }
    return (.success(body(filled)), 0)
  }

  // Clamp so the first attempt is neither empty nor already past the ceiling.
  var capacity = Swift.min(
    Swift.max(initialCapacity, alignment), Swift.max(maximumCapacity, alignment))

  // Try once on the stack, which is where the great majority of requests are
  // served, before falling back to the heap for the grown attempts.
  let (first, firstNextCapacity) = withUnsafeTemporaryAllocation(
    byteCount: capacity, alignment: alignment
  ) { buffer in
    attempt(into: buffer)
  }
  if let first { return first }
  capacity = firstNextCapacity

  while true {
    let buffer = UnsafeMutableRawBufferPointer.allocate(
      byteCount: capacity, alignment: alignment)
    defer { buffer.deallocate() }

    // Each retry at least doubles and `maximumCapacity` caps the growth, so
    // this terminates.
    let (result, nextCapacity) = attempt(into: buffer)
    if let result { return result }
    capacity = nextCapacity
  }
}

/// Locates one record of a chained information class within a filled buffer.
///
/// Every chained struct — `FILE_STREAM_INFO`, `FILE_FULL_DIR_INFO`,
/// `FILE_ID_BOTH_DIR_INFO`, `FILE_ID_EXTD_DIR_INFO` — begins with a `DWORD`
/// `NextEntryOffset` holding the distance in bytes to the following record, and
/// zero in the last one.
///
/// That offset comes from the file system, so it is validated rather than
/// trusted: the walk stops unless the next record's fixed part lies wholly
/// inside the buffer and starts strictly after this record's own fixed part.
/// The second condition is what guarantees forward progress, so a file system
/// reporting a zero-or-backwards offset ends the chain instead of spinning.
///
/// - Parameters:
///   - buffer: The filled buffer.
///   - offset: The byte offset of the record to locate.
///   - headerSize: The size of the record's fixed part, up to and including the
///     flexible array member's offset.
///
/// - Returns: The record's bytes, paired with the offset of the following
///   record or `nil` if this is the last one. Returns `nil` if `offset` does
///   not admit a whole fixed part, which means the buffer holds no record here.
@available(System 99, *)
@usableFromInline
internal func _fileInformationEntry(
  in buffer: UnsafeRawBufferPointer,
  at offset: Int,
  headerSize: Int
) -> (bytes: UnsafeRawBufferPointer, nextOffset: Int?)? {
  // Establish the invariant every read below depends on: the fixed part lies
  // wholly within the buffer. Written as a subtraction against `count` so it
  // cannot overflow for a large `offset`.
  guard headerSize > 0, offset >= 0, offset <= buffer.count - headerSize else {
    return nil
  }

  let next = Int(buffer.loadUnaligned(fromByteOffset: offset, as: DWORD.self))

  // Bytes left over after this record's fixed part; non-negative by the guard
  // above, so comparing against it cannot overflow either.
  let slack = buffer.count - offset - headerSize
  guard next >= headerSize, next <= slack else {
    // Zero ends the chain normally. Anything else here would overlap this
    // record or leave the buffer, and ends it too.
    return (UnsafeRawBufferPointer(rebasing: buffer[offset...]), nil)
  }
  return (
    UnsafeRawBufferPointer(rebasing: buffer[offset ..< offset + next]),
    offset + next
  )
}

/// The number of `WCHAR`s that fit in `byteCount` bytes of `record`, starting
/// at `offset`, after clamping to what the record actually holds.
///
/// `byteCount` is a length reported by the file system. Clamping it against the
/// record's real extent is what keeps a decode from reading past the end.
@available(System 99, *)
internal func _clampedWideLength(
  in record: UnsafeRawBufferPointer, offset: Int, byteCount: Int
) -> Int {
  guard offset >= 0, offset <= record.count else { return 0 }
  return Swift.max(0, Swift.min(byteCount, record.count - offset))
}

/// Decodes a run of `WCHAR` (UTF-16 code units) into a ``FilePath``.
///
/// The code units are copied verbatim into the path's storage. Note that
/// ill-formed UTF-16 (e.g. unpaired surrogates that Windows permits in
/// file names) is preserved.
///
/// - Parameters:
///   - base: A pointer to the first UTF-16 code unit.
///   - byteCount: The length of the name in bytes (as reported by the file
///     system), i.e. twice the number of code units.
@available(System 99, *)
@usableFromInline
internal func _decodeWideName(
  base: UnsafeRawPointer, byteCount: Int
) -> FilePath {
  let units = _loadWideUnits(base: base, byteCount: byteCount)
  guard !units.isEmpty else { return FilePath() }
  return FilePath(SystemString(nullTerminated: _nullTerminated(units)))
}

/// Decodes a run of `WCHAR` into a single ``FilePath/Component``, or `nil` if
/// the code units do not form one.
///
/// A directory entry names one component, so anything else — an empty name, or
/// a name containing a path separator — means the file system reported
/// something that cannot be represented, and is rejected rather than silently
/// reinterpreted as a multi-component path.
///
/// - Parameters:
///   - base: A pointer to the first UTF-16 code unit.
///   - byteCount: The length of the name in bytes, i.e. twice the number of
///     code units.
@available(System 99, *)
@usableFromInline
internal func _decodeWideComponent(
  base: UnsafeRawPointer, byteCount: Int
) -> FilePath.Component? {
  let units = _loadWideUnits(base: base, byteCount: byteCount)
  guard !units.isEmpty else { return nil }
  return FilePath.Component(SystemString(nullTerminated: _nullTerminated(units)))
}

/// Decodes a run of `WCHAR` into a `String`.
///
/// Unlike ``_decodeWideName``, this does not preserve ill-formed UTF-16:
/// unpaired surrogates are replaced with U+FFFD. It is used for the names that
/// are not paths, such as a data stream's `:name:$DATA`, and so have no
/// ``FilePath`` representation to preserve them in.
///
/// - Parameters:
///   - base: A pointer to the first UTF-16 code unit.
///   - byteCount: The length of the name in bytes, i.e. twice the number of
///     code units.
@available(System 99, *)
@usableFromInline
internal func _decodeWideString(
  base: UnsafeRawPointer, byteCount: Int
) -> String {
  String(decoding: _loadWideUnits(base: base, byteCount: byteCount),
         as: UTF16.self)
}

/// Copies out the UTF-16 code units in `byteCount` bytes at `base`, stopping at
/// the first NUL.
///
/// The kernel does not NUL-terminate the variable-length names in these
/// structs; it reports their length separately, and callers are expected to
/// have clamped `byteCount` to the record's extent already. Stopping at a NUL
/// anyway costs nothing and trims the fixed-width fields that *are* padded with
/// them, such as `FILE_ID_BOTH_DIR_INFO`'s `ShortName`.
@available(System 99, *)
@usableFromInline
internal func _loadWideUnits(
  base: UnsafeRawPointer, byteCount: Int
) -> [CInterop.PlatformChar] {
  let stride = MemoryLayout<WCHAR>.stride
  let unitCount = Swift.max(0, byteCount) / stride
  guard unitCount > 0 else { return [] }

  var units: [CInterop.PlatformChar] = []
  units.reserveCapacity(unitCount)
  for index in 0..<unitCount {
    let unit = base.loadUnaligned(
      fromByteOffset: index * stride, as: CInterop.PlatformChar.self)
    if unit == 0 { break }
    units.append(unit)
  }
  return units
}

/// Wraps loaded code units in the NUL-terminated `SystemChar` storage that
/// ``SystemString`` requires.
@available(System 99, *)
internal func _nullTerminated(
  _ units: [CInterop.PlatformChar]
) -> [SystemChar] {
  var storage: [SystemChar] = []
  storage.reserveCapacity(units.count + 1)
  for unit in units { storage.append(SystemChar(rawValue: unit)) }
  storage.append(.null)
  return storage
}

#endif // os(Windows)
