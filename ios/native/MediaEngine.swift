import Foundation

/// Metadata for one media stream. Field names match the JSON contract
/// produced by the native probe function.
public struct MediaStream: Sendable {
    public let index: Int
    public let codec: String
    public let type: String
    public let width: Int?
    public let height: Int?
    public let frameRate: Double?
    public let sampleRate: Int?
    public let channels: Int?
}

/// Container-level metadata.
public struct MediaMetadata: Sendable {
    public let duration: Int
    public let format: String
    public let bitrate: Int
    public let streams: [MediaStream]
}

/// Transcode options. Codecs name native encoders; defaults pick
/// hardware H.264 and AAC.
public struct TranscodeOptions: Sendable {
    public var videoCodec: String
    public var audioCodec: String

    public init(videoCodec: String = "h264_videotoolbox",
                audioCodec: String = "aac") {
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
    }
}

/// Media engine interface. Implementations must be safe to call from
/// any thread and must not block the main thread.
public protocol MediaEngine: Sendable {
    func probe(input: URL) async throws -> MediaMetadata
    func transcode(input: URL, output: URL, options: TranscodeOptions,
                   onProgress: @escaping @Sendable (Double) -> Void) async throws
    func cancel() async
    func capabilities() -> [String: Bool]
}

public enum MediaEngineError: Error {
    case probeFailed(Int32)
    case transcodeFailed(Int32)
    case cancelled
    case invalidMetadata
}

/// FFmpeg-backed engine. Calls into ffmpeg_bridge.h via a C header.
public final class FFmpegMediaEngine: MediaEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var currentBox: TranscodeBox?

    public init() {}

    public func probe(input: URL) async throws -> MediaMetadata {
        let path = input.path
        return try await Task.detached {
            var buf = [CChar](repeating: 0, count: 65536)
            let rc: Int32 = buf.withUnsafeMutableBufferPointer { ptr in
                ff_probe(path, ptr.baseAddress, Int32(ptr.count))
            }
            guard rc == 0 else { throw MediaEngineError.probeFailed(rc) }
            let text = buf.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
            return try Self.decodeMetadata(Data(text.utf8))
        }.value
    }

    public func transcode(input: URL, output: URL, options: TranscodeOptions,
                          onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let box = TranscodeBox(onProgress: onProgress)
        lock.withLock { currentBox = box }
        defer { lock.withLock { currentBox = nil } }
        let ctx = Unmanaged.passRetained(box).toOpaque()
        defer { Unmanaged<TranscodeBox>.fromOpaque(ctx).release() }
        let inPath = input.path
        let outPath = output.path
        let rc = await Task.detached {
            ff_transcode(inPath, outPath,
                         options.videoCodec, options.audioCodec,
                         { p, c in
                             Unmanaged<TranscodeBox>.fromOpaque(c!)
                                 .takeUnretainedValue().report(p)
                         },
                         { c in
                             Unmanaged<TranscodeBox>.fromOpaque(c!)
                                 .takeUnretainedValue().isCancelled ? 1 : 0
                         },
                         ctx)
        }.value
        if rc == -104 { throw MediaEngineError.cancelled }
        guard rc == 0 else { throw MediaEngineError.transcodeFailed(rc) }
    }

    public func cancel() async {
        lock.withLock { currentBox?.cancel() }
    }

    public func capabilities() -> [String: Bool] {
        ["h264": true, "hevc-decode": true, "aac": true, "mp3": true]
    }

    private final class TranscodeBox: @unchecked Sendable {
        private let lock = NSLock()
        private let onProgress: @Sendable (Double) -> Void
        private var cancelled = false

        init(onProgress: @escaping @Sendable (Double) -> Void) {
            self.onProgress = onProgress
        }

        func report(_ p: Double) { onProgress(p) }

        func cancel() { lock.withLock { cancelled = true } }

        var isCancelled: Bool { lock.withLock { cancelled } }
    }

    private static func decodeMetadata(_ data: Data) throws -> MediaMetadata {
        guard let json = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let duration = json["duration"] as? Int,
              let format = json["format"] as? String,
              let bitrate = json["bitrate"] as? Int,
              let rawStreams = json["streams"] as? [[String: Any]]
        else {
            throw MediaEngineError.invalidMetadata
        }
        let streams = rawStreams.map { s in
            MediaStream(
                index: s["index"] as? Int ?? 0,
                codec: s["codec"] as? String ?? "unknown",
                type: s["type"] as? String ?? "other",
                width: s["width"] as? Int,
                height: s["height"] as? Int,
                frameRate: (s["frameRate"] as? Double)
                    ?? (s["frameRate"] as? Int).map(Double.init),
                sampleRate: s["sampleRate"] as? Int,
                channels: s["channels"] as? Int)
        }
        return MediaMetadata(duration: duration, format: format,
                             bitrate: bitrate, streams: streams)
    }
}
