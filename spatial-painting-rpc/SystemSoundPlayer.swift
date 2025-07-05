//
//  SystemSoundPlayer.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/05/22.
//

import AVFoundation
import Foundation

enum SystemSound: UInt32 {
    case beginVideoRecording = 1117
    case endVideoRecording = 1118
    case cameraShutterSound = 1108

    var systemSoundID: SystemSoundID {
        self.rawValue as SystemSoundID
    }
}

public class SystemSoundPlayer {
    func play(systemSoundID: UInt32) {
        var soundIdRing: SystemSoundID = systemSoundID
        if let soundUrl = CFBundleCopyResourceURL(CFBundleGetMainBundle(), nil, nil, nil) {
            AudioServicesCreateSystemSoundID(soundUrl, &soundIdRing)
            AudioServicesPlaySystemSound(soundIdRing)
        }
    }

    func play(systemSound: SystemSound) {
        self.play(systemSoundID: systemSound.systemSoundID)
    }
}
