import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// One conversion result.
struct ConvResult: Identifiable, Sendable {
    let id = UUID()
    let source: URL
    let output: URL?
    let error: String?
    var ok: Bool { output != nil }
}

// UI stages.
enum Stage: Equatable {
    case idle
    case converting(current: Int, total: Int)
    case finished
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var stage: Stage = .idle
    @Published var isTargeted = false
    @Published var results: [ConvResult] = []

    // Output bit depth. Defaults to 16-bit (the format a colorist wants); the
    // choice is remembered across launches via UserDefaults.
    @Published var sixteenBit: Bool =
        (UserDefaults.standard.object(forKey: "use16BitPNG") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(sixteenBit, forKey: "use16BitPNG") }
    }

    var isConverting: Bool {
        if case .converting = stage { return true }
        return false
    }

    static let imageExts: Set<String> = ["heic", "heif", "png", "jpg", "jpeg", "tiff", "tif", "gif", "bmp"]

    // Kick off a batch. Runs conversion off the main thread; UI updates on the main actor.
    func handleDrop(_ urls: [URL]) {
        guard !isConverting else { return }
        let files = urls.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { return }
        results = []
        stage = .converting(current: 1, total: files.count)
        let bits = sixteenBit ? 16 : 8
        Task.detached(priority: .userInitiated) {
            var acc: [ConvResult] = []
            for (i, f) in files.enumerated() {
                await MainActor.run { self.stage = .converting(current: i + 1, total: files.count) }
                acc.append(Self.convert(f, bitsPerComponent: bits))
            }
            let finalResults = acc
            await MainActor.run {
                self.results = finalResults
                self.stage = .finished
            }
        }
    }

    func reset() {
        results = []
        stage = .idle
    }

    func revealInFinder() {
        let outs = results.compactMap { $0.output }
        guard !outs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outs)
    }

    // Pick an output path that never clobbers an existing file:
    // <name>-resolve.png, then -resolve-2.png, -resolve-3.png, …
    nonisolated static func uniqueOutputURL(for source: URL) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + "-resolve"
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(base + ".png")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).png")
            n += 1
        }
        return candidate
    }

    // The actual conversion — color-matched to sRGB, done in-process with
    // ImageIO + Core Graphics (the same colorimetric match `sips --matchTo` does,
    // but lets us choose 8- or 16-bit-per-component output). P3 gamut and PQ/HDR
    // are converted/clamped to sRGB; extreme HDR highlights are not tone-mapped.
    nonisolated static func convert(_ url: URL, bitsPerComponent: Int) -> ConvResult {
        let outURL = uniqueOutputURL(for: url)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB) else {
            return ConvResult(source: url, output: nil, error: "Couldn't read image")
        }
        let w = img.width, h = img.height
        // 16-bit RGBA needs the byteOrder16Little flag per CGContext's supported
        // formats; 8-bit RGBA uses the default byte order. Premultiplied alpha
        // preserves any transparency (iPhone HEIC stills are opaque, so it's a
        // no-op for them).
        let alpha = CGImageAlphaInfo.premultipliedLast.rawValue
        let info = bitsPerComponent == 16
            ? alpha | CGBitmapInfo.byteOrder16Little.rawValue
            : alpha
        let bytesPerRow = w * (bitsPerComponent / 8) * 4
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                  space: srgb, bitmapInfo: info) else {
            return ConvResult(source: url, output: nil, error: "Couldn't create \(bitsPerComponent)-bit context")
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)) // CG color-matches P3/PQ -> sRGB
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                            UTType.png.identifier as CFString, 1, nil) else {
            return ConvResult(source: url, output: nil, error: "Couldn't write PNG")
        }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else {
            return ConvResult(source: url, output: nil, error: "Couldn't write PNG")
        }
        return ConvResult(source: url, output: outURL, error: nil)
    }
}

struct ContentView: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        Group {
            switch model.stage {
            case .idle:
                DropZone(model: model, targeted: model.isTargeted)
            case let .converting(current, total):
                Converting(current: current, total: total)
            case .finished:
                Done(model: model)
            }
        }
        .frame(width: 460, height: 380)
        .onDrop(of: [.fileURL], isTargeted: $model.isTargeted) { providers in
            guard !model.isConverting else { return false }
            loadURLs(providers) { urls in
                Task { @MainActor in model.handleDrop(urls) }
            }
            return true
        }
    }

    // Pull file URLs out of dropped item providers. Finder drops usually arrive as a
    // file-URL Data blob; we also accept URL/String forms. Accumulation is lock-guarded
    // because provider callbacks can fire on different threads.
    private func loadURLs(_ providers: [NSItemProvider], _ completion: @escaping ([URL]) -> Void) {
        let typeID = UTType.fileURL.identifier
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for p in providers where p.hasItemConformingToTypeIdentifier(typeID) {
            group.enter()
            p.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                var url: URL?
                switch item {
                case let data as Data:
                    url = URL(dataRepresentation: data, relativeTo: nil)
                case let u as URL:
                    url = u
                case let s as String:
                    url = URL(string: s)
                default:
                    url = nil
                }
                if let u = url, u.isFileURL {
                    lock.lock(); urls.append(u); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

struct DropZone: View {
    @ObservedObject var model: Model
    let targeted: Bool
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("Drop HEIC here")
                .font(.title2.weight(.semibold))
            Text("Converts to sRGB PNG for DaVinci Resolve")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Output depth", selection: $model.sixteenBit) {
                Text("8-bit").tag(false)
                Text("16-bit").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [9])
                )
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .padding(22)
        )
    }
}

struct Converting: View {
    let current: Int
    let total: Int
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(total > 1 ? "Converting \(current) of \(total)…" : "Converting…")
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Done: View {
    @ObservedObject var model: Model

    var body: some View {
        let ok = model.results.filter(\.ok).count
        let fail = model.results.count - ok
        VStack(spacing: 14) {
            Image(systemName: fail == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(fail == 0 ? Color.green : Color.orange)
            Text(headline(ok: ok, fail: fail))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if fail > 0, let e = model.results.first(where: { !$0.ok })?.error {
                Text(e)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 28)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                if ok > 0 {
                    Button("Show in Finder") { model.revealInFinder() }
                }
                Button("Convert another") { model.reset() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func headline(ok: Int, fail: Int) -> String {
        if fail == 0 {
            return ok == 1 ? "Done — 1 file converted" : "Done — \(ok) files converted"
        }
        return "\(ok) converted, \(fail) failed"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Files dropped on the Dock/Finder icon (modern API).
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Model.shared.handleDrop(urls) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Older API, kept as a fallback for some launch paths.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        Task { @MainActor in Model.shared.handleDrop(filenames.map { URL(fileURLWithPath: $0) }) }
        NSApp.activate(ignoringOtherApps: true)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@main
struct HEICToResolveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
