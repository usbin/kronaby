import AVFoundation
import MediaPlayer
import UIKit

final class FindMyPhone {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var previousVolume: Float?

    func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // 현재 볼륨 저장 → 최대로
            previousVolume = AVAudioSession.sharedInstance().outputVolume
            MPVolumeView.setVolume(1.0)

            let soundURL = URL(fileURLWithPath: "/System/Library/Audio/UISounds/alarm.caf")
            player = try AVAudioPlayer(contentsOf: soundURL)
            player?.numberOfLoops = -1
            player?.volume = 1.0
            player?.play()

            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            for i in 0..<10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                    AudioServicesPlayAlertSound(SystemSoundID(1005))
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil

        // 볼륨 복원
        if let vol = previousVolume {
            MPVolumeView.setVolume(vol)
            previousVolume = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
    }
}