import AppKit
import AVKit

final class PopupModel: ObservableObject {
    @Published private(set) var capture: Capture
    @Published private(set) var image: NSImage?
    @Published private(set) var subtitle = ""
    @Published var editor: EditorModel?
    private(set) var video: VideoModel?
    private(set) var pixelSize = CGSize.zero
    private(set) var pixelsPerPoint: CGFloat = 1

    /// Videos are loaded asynchronously first (`VideoModel.load`) and passed in.
    init(capture: Capture, video: VideoModel? = nil) {
        self.capture = capture
        self.video = video
        load()
    }

    var isLoaded: Bool { capture.kind == .video ? video != nil : image != nil }

    func replace(with capture: Capture) {
        self.capture = capture
        load()
    }

    private func load() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: capture.url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let fileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)

        switch capture.kind {
        case .image:
            video = nil
            guard let loaded = ImageFiles.load(capture.url) else {
                image = nil
                return
            }
            pixelSize = CGSize(width: loaded.image.width, height: loaded.image.height)
            pixelsPerPoint = loaded.pixelsPerPoint
            image = NSImage(cgImage: loaded.image, size: NSSize(width: pixelSize.width / pixelsPerPoint,
                                                                height: pixelSize.height / pixelsPerPoint))
            subtitle = "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) · \(fileSize)"
        case .video:
            guard let video else { return }
            image = nil
            pixelSize = video.naturalSize
            pixelsPerPoint = NSScreen.main?.backingScaleFactor ?? 2
            subtitle = "\(video.durationText) · \(Int(pixelSize.width)) × \(Int(pixelSize.height)) · \(fileSize)"
        }
    }
}

final class VideoModel: ObservableObject {
    let player: AVPlayer
    let naturalSize: CGSize
    let duration: Double
    weak var playerView: AVPlayerView?
    var isTrimming = false

    private init(asset: AVURLAsset, naturalSize: CGSize, duration: Double) {
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = true
        self.naturalSize = naturalSize
        self.duration = duration
    }

    /// Reads the video's size and length off the main thread, then calls back on the main queue.
    static func load(_ url: URL, completion: @escaping (VideoModel) -> Void) {
        Task {
            let asset = AVURLAsset(url: url)
            var size = CGSize(width: 1280, height: 720)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let rotated = natural.applying(transform)
                size = CGSize(width: abs(rotated.width), height: abs(rotated.height))
            }
            let seconds = (try? await asset.load(.duration))?.seconds ?? 0
            let duration = seconds.isFinite ? seconds : 0
            let finalSize = size
            await MainActor.run {
                completion(VideoModel(asset: asset, naturalSize: finalSize, duration: duration))
            }
        }
    }

    deinit { player.pause() }

    var durationText: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func togglePlayback() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }
}
