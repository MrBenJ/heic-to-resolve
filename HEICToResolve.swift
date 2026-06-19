import SwiftUI
import AppKit
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
    case converting(done: Int, total: Int)
    case finished
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var stage: Stage = .idle
    @Published var isTargeted = false
    @Published var results: [ConvResult] = []

    var isConverting: Bool {
        if case .converting = stage { return true }
        return false
    }

    static let imageExts: Set<String> = ["heic", "heif", "png", "jpg", "jpeg", "tiff", "tif", "gif", "bmp"]

    // Kick off a batch. Runs sips off the main thread; UI updates on the main actor.
    func handleDrop(_ urls: [URL]) {
        guard !isConverting else { return }
        let files = urls.filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { return }
        results = []
        stage = .converting(done: 0, total: files.count)
        Task.detached(priority: .userInitiated) {
            var acc: [ConvResult] = []
            for (i, f) in files.enumerated() {
                let r = Self.convert(f)
                acc.append(r)
                let done = i + 1
                await MainActor.run { self.stage = .converting(done: done, total: files.count) }
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

    // The actual conversion — the exact sips command, color-matched to sRGB.
    nonisolated static func convert(_ url: URL) -> ConvResult {
        let srgb = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
        let outName = url.deletingPathExtension().lastPathComponent + "-resolve.png"
        let outURL = url.deletingLastPathComponent().appendingPathComponent(outName)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["--matchTo", srgb, "-s", "format", "png", url.path, "--out", outURL.path]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if proc.terminationStatus == 0 {
                return ConvResult(source: url, output: outURL, error: nil)
            }
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "sips exited \(proc.terminationStatus)"
            return ConvResult(source: url, output: nil, error: msg)
        } catch {
            return ConvResult(source: url, output: nil, error: error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        Group {
            switch model.stage {
            case .idle:
                DropZone(targeted: model.isTargeted)
            case let .converting(done, total):
                Converting(done: done, total: total)
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

    // Pull file URLs out of dropped item providers (thread-safe accumulation).
    private func loadURLs(_ providers: [NSItemProvider], _ completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let u = url {
                    lock.lock(); urls.append(u); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

struct DropZone: View {
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
    let done: Int
    let total: Int
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(total > 1 ? "Converting \(min(done + 1, total)) of \(total)…" : "Converting…")
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
