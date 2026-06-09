import AudioToolbox
import CoreAudio
import Foundation
import os

public struct TapStreamFormat: Sendable {
    public let sampleRate: Double
    public let channels: Int
}

public enum TapError: Error, LocalizedError {
    case processNotRunning(String)
    case osStatus(String, OSStatus)

    public var errorDescription: String? {
        switch self {
        case .processNotRunning(let bundleID):
            "\(bundleID) is not running"
        case .osStatus(let stage, let status):
            "\(stage) failed (OSStatus \(status)) — if this is a permission " +
            "problem, check System Settings → Privacy & Security → Screen & " +
            "System Audio Recording → System Audio Recording Only"
        }
    }
}

/// Captures another process's audio output via a Core Audio process tap
/// (macOS 14.4+), muting the process for the user. Captured PCM is fanned
/// out to one or more ring buffers (playback + analysis).
///
/// Lifecycle: activate(pid:) → startCapture(into:) → stop().
/// First AudioHardwareCreateProcessTap triggers the system audio recording
/// permission prompt (NSAudioCaptureUsageDescription).
public final class ProcessTapController {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "ProcessTap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "csh.tap-ioproc", qos: .userInteractive)

    public private(set) var format: TapStreamFormat?
    private var rings: [AudioRingBuffer] = []
    /// Scratch for interleaving if the tap delivers split buffers.
    private var scratch: UnsafeMutablePointer<Float>?
    private let scratchCapacityFrames = 16384

    public init() {}

    deinit {
        stop()
    }

    /// Creates the (muting) tap on the target process and reads its format.
    public func activate(pid: pid_t) throws -> TapStreamFormat {
        // PID → Core Audio process object.
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var pidValue = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &processObject
        )
        guard status == noErr, processObject != kAudioObjectUnknown else {
            throw TapError.osStatus("translate PID to process object", status)
        }

        // The tap itself — muted: the user hears only our delayed replay.
        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "CommandShiftHero-tap"

        status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw TapError.osStatus("create process tap", status)
        }
        tapUUID = description.uuid

        // Tap stream format.
        var asbd = AudioStreamBasicDescription()
        address.mSelector = kAudioTapPropertyFormat
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw TapError.osStatus("read tap format", status)
        }

        let format = TapStreamFormat(sampleRate: asbd.mSampleRate,
                                     channels: Int(asbd.mChannelsPerFrame))
        self.format = format
        Self.log.info("tap active: \(format.sampleRate)Hz \(format.channels)ch")
        return format
    }

    private var tapUUID = UUID()

    /// Builds the aggregate device around the tap and starts the IOProc,
    /// fanning captured frames into every ring (e.g. playback + analysis).
    public func startCapture(into targetRings: [AudioRingBuffer]) throws {
        guard format != nil else {
            throw TapError.osStatus("startCapture before activate", -1)
        }
        rings = targetRings
        scratch = .allocate(capacity: scratchCapacityFrames * (format?.channels ?? 2))

        // Default system output device UID for the aggregate's sub-device.
        var outputDevice = AudioDeviceID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &outputDevice
        )
        guard status == noErr else {
            throw TapError.osStatus("get default output device", status)
        }

        var uidCF: CFString = "" as CFString
        address.mSelector = kAudioDevicePropertyDeviceUID
        size = UInt32(MemoryLayout<CFString>.size)
        status = withUnsafeMutablePointer(to: &uidCF) { ptr in
            AudioObjectGetPropertyData(outputDevice, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else {
            throw TapError.osStatus("get output device UID", status)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CommandShiftHero-aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: uidCF as String]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                ]
            ],
        ]

        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw TapError.osStatus("create aggregate device", status)
        }

        let rings = self.rings
        let scratch = self.scratch!
        let scratchCapacity = scratchCapacityFrames

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInputData, _, _, _ in
            // Hot path: copy tap PCM into the rings, nothing else.
            let abl = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inInputData)
            )
            guard abl.count > 0 else { return }

            if abl.count == 1 {
                // Interleaved (the normal stereo-mixdown case).
                let buffer = abl[0]
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
                let channels = max(1, Int(buffer.mNumberChannels))
                let frames = Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size)
                for ring in rings {
                    ring.write(data, frameCount: frames)
                }
            } else {
                // Split buffers: interleave into scratch first.
                let channels = abl.count
                let frames = min(Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size, scratchCapacity)
                for c in 0..<channels {
                    guard let src = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for n in 0..<frames {
                        scratch[n * channels + c] = src[n]
                    }
                }
                for ring in rings {
                    ring.write(scratch, frameCount: frames)
                }
            }
        }
        guard status == noErr, procID != nil else {
            throw TapError.osStatus("create IOProc", status)
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            throw TapError.osStatus("start aggregate device", status)
        }
        Self.log.info("capture started (\(targetRings.count) rings)")
    }

    public func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        scratch?.deallocate()
        scratch = nil
        rings = []
    }
}
