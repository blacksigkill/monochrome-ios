import SwiftUI
import AVFoundation

@main
struct MonochromeIOSApp: App {
    @State private var audioPlayerService = AudioPlayerService()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(audioPlayerService)
                .onAppear {
                    setupAudioSession()
                }
        }
    }
    
    private func setupAudioSession() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("AVAudioSession configured for playback.")
        } catch {
            print("Failed to set up AVAudioSession: \(error.localizedDescription)")
        }
#endif
    }
}
