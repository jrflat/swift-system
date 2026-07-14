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

// MARK: - Fixed-size info classes

/// A fixed-size file-information struct that can be retrieved from a single
/// call to `GetFileInformationByHandleEx`.
///
/// Types conforming to this protocol know which
/// ``FileInfoClass`` selects them.
/// The type requested with ``FileDescriptor/fileInformation(_:)``
/// determines the info class that is fetched.
///
/// - Note: This protocol is only for the *fixed-size* classes. Variable-length
///   classes such as the file name (`FileNameInfo`) and directory enumeration
///   classes require a growable buffer and are exposed through dedicated APIs.
///
/// - Note: Only available on Windows.
@available(System 99, *)
public protocol FileInfoByHandle: RawRepresentable {
  /// The info class that selects this structure.
  @_alwaysEmitIntoClient
  static var infoClass: FileInfoClass { get }
}

@available(System 99, *)
extension FileBasicInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .basic }
}

@available(System 99, *)
extension FileStandardInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .standard }
}

@available(System 99, *)
extension FileIDInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .id }
}

@available(System 99, *)
extension FileAttributeTagInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .attributeTag }
}

@available(System 99, *)
extension FileStorageInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .storage }
}

@available(System 99, *)
extension FileAlignmentInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .alignment }
}

@available(System 99, *)
extension FileCompressionInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .compression }
}

// MARK: - FileDescriptor API

@available(System 99, *)
extension FileDescriptor {
  /// Retrieves fixed-size file information for this file descriptor.
  ///
  /// The type of information retrieved is determined by the requested type. For
  /// example, requesting ``FileStandardInfo`` retrieves the file's sizes and
  /// link count:
  ///
  ///     let info = try fd.fileInformation(FileStandardInfo.self)
  ///     print(info.size, info.linkCount)
  ///
  /// - Parameter type: The information struct type to retrieve.
  /// - Returns: The requested information.
  ///
  /// The corresponding C function is `GetFileInformationByHandleEx`.
  @_alwaysEmitIntoClient
  public func fileInformation<Info: FileInfoByHandle>(
    _ type: Info.Type = Info.self
  ) throws(Errno) -> Info {
    try _fileInformation(type).get()
  }

  @usableFromInline
  internal func _fileInformation<Info: FileInfoByHandle>(
    _ type: Info.Type
  ) -> Result<Info, Errno> {
    // Allocate `stride` (not `size`) bytes; the kernel validates dwBufferSize
    // against the C `sizeof(Info)`, which includes trailing padding.
    return withUnsafeTemporaryAllocation(
      byteCount: MemoryLayout<Info.RawValue>.stride,
      alignment: MemoryLayout<Info.RawValue>.alignment
    ) { buffer in
      buffer.initializeMemory(as: UInt8.self, repeating: 0)
      guard system_getFileInformationByHandleEx(
        self.rawValue, Info.infoClass.rawValue, buffer
      ) else {
        return .failure(Errno.current)
      }
      let raw = buffer.load(as: Info.RawValue.self)
      guard let info = Info(rawValue: raw) else {
        return .failure(Errno.invalidArgument)
      }
      return .success(info)
    }
  }

  /// Retrieves the name of the file referred to by this file descriptor.
  ///
  /// The returned path is the location of the file relative to the root of its
  /// volume; it does not include a drive letter. For example, a handle to
  /// `C:\dir\file.txt` yields `\dir\file.txt`.
  ///
  /// - Parameter normalized: When `true`, retrieves the normalized name
  ///   (`FileNormalizedNameInfo`); when `false` (default), retrieves the
  ///   name as opened (`FileNameInfo`).
  /// - Returns: The file's name, as a path relative to its volume root.
  ///
  /// The corresponding C function is `GetFileInformationByHandleEx` with the
  /// `FileNameInfo` or `FileNormalizedNameInfo` information class.
  @_alwaysEmitIntoClient
  public func fileName(
    normalized: Bool = false
  ) throws(Errno) -> FilePath {
    try _fileName(normalized: normalized).get()
  }

  @usableFromInline
  internal func _fileName(
    normalized: Bool
  ) -> Result<FilePath, Errno> {
    // FILE_NAME_INFO is variable-length: a DWORD FileNameLength (in bytes)
    // followed by a WCHAR FileName[] array. Start with a stack-friendly guess
    // and grow on ERROR_MORE_DATA, which signals the buffer was too small.
    let infoClass = if normalized {
      WinSDK.FileNormalizedNameInfo
    } else {
      WinSDK.FileNameInfo
    }

    let headerSize = MemoryLayout<FILE_NAME_INFO>.offset(of: \.FileName)!
    let initialCapacity = headerSize + Int(MAX_PATH) * MemoryLayout<WCHAR>.stride

    enum Attempt {
      case done(Result<FilePath, Errno>)
      case grow(nextCapacity: Int)
    }

    func attempt(
      into buffer: UnsafeMutableRawBufferPointer
    ) -> Attempt {
      buffer.initializeMemory(as: UInt8.self, repeating: 0)

      let err = system_getFileInformationByHandleEx_error(
        self.rawValue, infoClass, buffer)

      let reportedLength = Int(buffer.loadUnaligned(
        fromByteOffset: 0, as: DWORD.self))

      if err == ERROR_MORE_DATA {
        // FileNameLength should hold the required length, but grow dynamically
        // and take the max so a driver that under-reports can't stall progress.
        return .grow(nextCapacity: Swift.max(headerSize + reportedLength, buffer.count * 2))
      }
      guard err == ERROR_SUCCESS else {
        return .done(.failure(Errno(windowsError: err)))
      }

      let name = _decodeWideName(
        base: buffer.baseAddress!.advanced(by: headerSize),
        byteCount: reportedLength)
      return .done(.success(name))
    }

    var capacity = initialCapacity
    let first = withUnsafeTemporaryAllocation(
      byteCount: initialCapacity,
      alignment: MemoryLayout<FILE_NAME_INFO>.alignment
    ) { buffer in
      attempt(into: buffer)
    }
    switch first {
    case .done(let result):
      return result
    case .grow(let nextCapacity):
      capacity = nextCapacity
    }

    while true {
      let buffer = UnsafeMutableRawBufferPointer.allocate(
        byteCount: capacity, alignment: MemoryLayout<FILE_NAME_INFO>.alignment)
      defer { buffer.deallocate() }

      switch attempt(into: buffer) {
      case .done(let result):
        return result
      case .grow(let nextCapacity):
        capacity = nextCapacity
      }
    }
  }
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
  let unitCount = byteCount / MemoryLayout<WCHAR>.stride
  guard unitCount > 0 else { return FilePath() }
  // The kernel does not null-terminate the name, so append a NUL for
  // `SystemString`'s null-terminated storage.
  let storage = Array<SystemChar>(
    unsafeUninitializedCapacity: unitCount + 1
  ) { buffer, initialized in
    for i in 0..<unitCount {
      let unit = base.loadUnaligned(
        fromByteOffset: i * MemoryLayout<WCHAR>.stride,
        as: CInterop.PlatformChar.self)
      buffer[i] = SystemChar(rawValue: unit)
    }
    buffer[unitCount] = .null
    initialized = unitCount + 1
  }
  return FilePath(SystemString(nullTerminated: storage))
}

#endif // os(Windows)
