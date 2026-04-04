import AVFoundation
import UIKit

final class FindMyPhone {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play() {
        do {
            // .playback 카테고리 = 무음모드 무시, 최대 볼륨
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // iOS 시스템 사운드 파일 사용 (번들 불필요)
            let soundURL = URL(fileURLWithPath: "/System/Library/Audio/UISounds/alarm.caf")
            player = try AVAudioPlayer(contentsOf: soundURL)
            player?.numberOfLoops = -1  // 무한 반복
            player?.volume = 1.0
            player?.play()

            // 30초 후 자동 정지
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            // Fallback: 시스템 알림음 반복
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
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
