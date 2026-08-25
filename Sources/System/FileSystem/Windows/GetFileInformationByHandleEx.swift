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
/// - Note: This protocol is only for the *fixed-size* classes, which are the
///   ones whose C struct has a size to wrap. The classes whose struct ends in a
///   flexible array member have dedicated APIs instead:
///   ``FileDescriptor/fileName(normalized:)``,
///   ``FileDescriptor/dataStreams()``, and
///   ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)``.
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

@available(System 99, *)
extension FileCaseSensitiveInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .caseSensitive }
}

@available(System 99, *)
extension FileRemoteProtocolInfo: FileInfoByHandle {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .remoteProtocol }
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
  /// - Precondition: This descriptor must not refer to a pipe.
  ///
  /// Not every information class applies to every handle: ``FileIDInfo``
  /// requires a file system that reports identifiers,
  /// ``FileRemoteProtocolInfo`` requires a remote file, and
  /// ``FileCaseSensitiveInfo`` requires a directory. Windows rejects a class it
  /// cannot serve, which surfaces here as ``Errno/invalidArgument`` or
  /// ``Errno/notSupported`` depending on the file system.
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

  /// Retrieves file information of the given class into a buffer this function
  /// owns, and passes it to `body`.
  ///
  /// This is the escape hatch for information classes that ``System`` does not
  /// model. Every class it does model has a dedicated API, which you should
  /// prefer:
  ///
  /// | Class                    | API                                       |
  /// | ------------------------ | ----------------------------------------- |
  /// | the fixed-size classes   | ``fileInformation(_:)``                   |
  /// | ``FileInfoClass/name``   | ``fileName(normalized:)``                 |
  /// | ``FileInfoClass/stream`` | ``dataStreams()``                         |
  /// | the directory classes    | ``withDirectoryEntries(_:bufferSize:_:)`` |
  ///
  /// The buffer is allocated, aligned, zero-filled, and grown on
  /// `ERROR_MORE_DATA` by this function, and released when it returns. It is
  /// read-only and valid only for the duration of `body`; copy out anything that
  /// needs to outlive the call.
  ///
  /// Interpreting the bytes is up to you, and is unsafe in the ways the modelled
  /// APIs exist to avoid. In particular, the chained classes return a run of
  /// variable-length records linked by a `NextEntryOffset` member that the file
  /// system chooses, and using one to advance a pointer without first bounding
  /// it against the buffer is an out-of-bounds read.
  ///
  /// - Parameters:
  ///   - infoClass: The class of information to retrieve.
  ///   - minimumCapacity: The size of the first attempt, in bytes.
  ///   - maximumCapacity: The largest buffer to grow to before giving up with
  ///     ``Errno/outOfRange``.
  ///   - body: Receives the filled buffer. Note that only the bytes the file
  ///     system wrote are meaningful; the rest are zero.
  /// - Returns: Whatever `body` returns.
  ///
  /// - Precondition: This descriptor must not refer to a pipe.
  ///
  /// The corresponding C function is `GetFileInformationByHandleEx`.
  @_alwaysEmitIntoClient
  public func withUnsafeFileInformation<R>(
    _ infoClass: FileInfoClass,
    minimumCapacity: Int = 4096,
    maximumCapacity: Int = 16 << 20,
    _ body: (UnsafeRawBufferPointer) throws -> R
  ) throws -> R {
    try _withUnsafeFileInformation(
      infoClass,
      minimumCapacity: minimumCapacity,
      maximumCapacity: maximumCapacity,
      body)
  }

  @usableFromInline
  internal func _withUnsafeFileInformation<R>(
    _ infoClass: FileInfoClass,
    minimumCapacity: Int,
    maximumCapacity: Int,
    _ body: (UnsafeRawBufferPointer) throws -> R
  ) throws -> R {
    let outcome = _withFileInformationBuffer(
      fileDescriptor: self.rawValue,
      infoClass: infoClass.rawValue,
      initialCapacity: minimumCapacity,
      maximumCapacity: maximumCapacity,
      // The chained classes place 8-byte members at fixed offsets, so 8 is the
      // alignment the file system needs regardless of the class requested.
      alignment: 8,
      // No class that reaches this API reports a required size.
      capacityHint: { _ in 0 }
    ) { buffer in
      // `body`'s own error is carried out through the non-throwing driver.
      Result { try body(buffer) }
    }

    switch outcome {
    case .success(let value):
      return try value.get()
    case .failure(let error):
      throw Errno(windowsError: error.code)
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
  /// - Precondition: This descriptor must not refer to a pipe.
  ///
  /// - Note: Not every SMB server can produce a normalized name; requesting
  ///   one for a file on such a share fails.
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
    // followed by a WCHAR FileName[] array.
    let infoClass = normalized
      ? FileInfoClass.normalizedName.rawValue
      : FileInfoClass.name.rawValue

    let headerSize = MemoryLayout<FILE_NAME_INFO>.offset(of: \.FileName)!
    let unitSize = MemoryLayout<WCHAR>.stride

    let result = _withFileInformationBuffer(
      fileDescriptor: self.rawValue,
      infoClass: infoClass,
      // A stack-friendly guess that serves nearly every path.
      initialCapacity: headerSize + Int(MAX_PATH) * unitSize,
      // Windows bounds a path at 32767 code units, so a request past that is a
      // misbehaving file system rather than a buffer that needs growing.
      maximumCapacity: headerSize + _maximumWidePathLength * unitSize,
      alignment: MemoryLayout<FILE_NAME_INFO>.alignment,
      // FileNameLength holds the required length even when the buffer was too
      // small, so the retry can size itself in one step.
      capacityHint: { buffer in
        headerSize
          + Int(buffer.loadUnaligned(fromByteOffset: 0, as: DWORD.self))
      }
    ) { buffer -> FilePath in
      guard let base = buffer.baseAddress else { return FilePath() }
      let reportedLength = Int(
        buffer.loadUnaligned(fromByteOffset: 0, as: DWORD.self))
      // Clamp: success means the name fit, but the length still arrives from
      // the file system and is not trusted to bound a read.
      return _decodeWideName(
        base: base.advanced(by: headerSize),
        byteCount: Swift.min(
          reportedLength, Swift.max(0, buffer.count - headerSize)))
    }

    return result.mapError { Errno(windowsError: $0.code) }
  }
}

#endif // os(Windows)
