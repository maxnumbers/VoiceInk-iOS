//
//  VoiceInk_iosApp.swift
//  VoiceInk-ios
//
//  Created by Prakash Joshi on 12/08/2025.
//

import SwiftUI
import SwiftData

@main
struct VoiceInk_iosApp: App {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var httpServer: VoiceInkHTTPServer

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Clear any stale recording state on app launch
        AppGroupCoordinator.shared.updateRecordingState(false)
        print("🧹 Cleared stale recording state on app launch")

        // Initialize HTTP server
        let recordingMgr = RecordingManager()
        _recordingManager = StateObject(wrappedValue: recordingMgr)
        _httpServer = StateObject(wrappedValue: VoiceInkHTTPServer(
            port: 8080,
            recordingManager: recordingMgr,
            modelContainer: Self.sharedModelContainer
        ))
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(recordingManager)
                    .environmentObject(httpServer)
                    .onAppear {
                        httpServer.start()
                        print("🌐 HTTP Server started for ESP32 integration")
                    }
                    .onOpenURL { url in
                        handleURL(url)
                    }
            } else {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
                    .onOpenURL { url in
                        handleURL(url)
                    }
            }
        }
        .modelContainer(Self.sharedModelContainer)
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "voiceink" else { return }
        
        switch url.host {
        case "record":
            print("🔗 URL scheme triggered: open app for recording")
            // Automatically start recording flow when opened from keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.recordingManager.startRecordingFlow()
            }
            print("📱 App opened via keyboard extension - starting recording")
        default:
            break
        }
    }
}
