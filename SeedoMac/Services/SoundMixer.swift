// SeedoMac/Services/SoundMixer.swift
import Foundation
import AVFoundation

class SoundMixer: ObservableObject {
    static let shared = SoundMixer()
    
    struct Track: Identifiable {
        let id: String
        let name: String
        let fileName: String
        var volume: Float
        var isPlaying: Bool
    }
    
    @Published var tracks: [Track] = [
        Track(id: "rain", name: "Rain", fileName: "rain.mp3", volume: 0, isPlaying: false),
        Track(id: "waves", name: "Waves", fileName: "waves.mp3", volume: 0, isPlaying: false),
        Track(id: "birds", name: "Birds", fileName: "birds.mp3", volume: 0, isPlaying: false),
        Track(id: "fire", name: "Fire", fileName: "fire.mp3", volume: 0, isPlaying: false),
        Track(id: "wind", name: "Wind", fileName: "wind.mp3", volume: 0, isPlaying: false)
    ]
    
    private var players: [String: AVAudioPlayer] = [:]
    private var customSoundsPath: String = ""
    
    func setCustomPath(_ path: String) {
        self.customSoundsPath = path
        // Refresh players if path changes
    }
    
    func updateVolume(id: String, volume: Float) {
        if let index = tracks.firstIndex(where: { $0.id == id }) {
            tracks[index].volume = volume
            tracks[index].isPlaying = volume > 0
            
            if volume > 0 {
                playTrack(id)
            } else {
                stopTrack(id)
            }
            
            players[id]?.volume = volume
        }
    }
    
    private func playTrack(_ id: String) {
        if players[id]?.isPlaying == true { return }
        
        let track = tracks.first { $0.id == id }!
        let url: URL?
        
        // Try Custom path first
        let customFileURL = URL(fileURLWithPath: customSoundsPath).appendingPathComponent(track.fileName)
        if FileManager.default.fileExists(atPath: customFileURL.path) {
            url = customFileURL
        } else {
            // Internal bundle
            url = Bundle.main.url(forResource: track.id, withExtension: "mp3")
        }
        
        guard let finalUrl = url else { return }
        
        do {
            let player = try AVAudioPlayer(contentsOf: finalUrl)
            player.numberOfLoops = -1
            player.volume = track.volume
            player.play()
            players[id] = player
        } catch {
            print("Failed to play track \(id): \(error)")
        }
    }
    
    private func stopTrack(_ id: String) {
        players[id]?.stop()
        players[id] = nil
    }
    
    func stopAll() {
        for id in players.keys {
            stopTrack(id)
        }
        for i in 0..<tracks.count {
            tracks[i].volume = 0
            tracks[i].isPlaying = false
        }
    }
}
