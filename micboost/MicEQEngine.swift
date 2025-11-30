import Foundation
internal import AVFoundation
import Combine
import CoreMedia
import CoreAudio
import AudioToolbox

class MicEQEngine: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    
    private let captureSession = AVCaptureSession()
    private let captureOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "audio.capture")
    
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var isBlackHoleFound = true
    
    private var userIntentRunning = false
    
    // Microphone Selection
    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var selectedMicrophoneID: String = "" {
        didSet {
            if oldValue != selectedMicrophoneID {
                configureInputDevice()
            }
        }
    }
    
    // EQ Parameters
    @Published var masterGain: Float = 6.0 {
        didSet { updateEQ() }
    }
    @Published var bassGain: Float = 5.0 {
        didSet { updateEQ() }
    }
    @Published var midGain: Float = -3.0 {
        didSet { updateEQ() }
    }
    @Published var trebleGain: Float = 4.0 {
        didSet { updateEQ() }
    }
    
    override init() {
        super.init()
        discoverMicrophones()
        setupEngine()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEngineConfigurationChange), name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCaptureSessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: captureSession)
    }
    
    @objc private func handleEngineConfigurationChange(notification: Notification) {
        print("⚠️ Audio Engine Configuration Changed")
        if userIntentRunning {
            print("🔄 Configuration changed. Enforcing BlackHole routing...")
            
            // Stop the engine to force a reset of the output node connection
            if engine.isRunning {
                engine.stop()
            }
            
            // Restart everything
            startSession()
        }
    }
    
    @objc private func handleCaptureSessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("⚠️ Capture Session Runtime Error: \(error.localizedDescription)")
        
        if userIntentRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    private func discoverMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
        
        // Select default if none selected
        if selectedMicrophoneID.isEmpty {
            // Try to find the system default input
            var defaultDeviceID = AudioDeviceID(0)
            var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &propertySize,
                &defaultDeviceID
            )
            
            if status == noErr {
                // Find the AVCaptureDevice that matches this AudioDeviceID
                if let match = availableMicrophones.first(where: {
                    // AVCaptureDevice uniqueID is usually the UID string, but we can try to match by name or other properties if needed.
                    // However, for CoreAudio devices, uniqueID often corresponds to the UID.
                    // Let's try to match by UID.
                    return getAudioDeviceUID(id: defaultDeviceID) == $0.uniqueID
                }) {
                    selectedMicrophoneID = match.uniqueID
                } else if let first = availableMicrophones.first {
                     selectedMicrophoneID = first.uniqueID
                }
            } else if let first = availableMicrophones.first {
                selectedMicrophoneID = first.uniqueID
            }
        }
    }
    
    private func getAudioDeviceUID(id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr else { return nil }
        
        var uidString: CFString? = nil
        let status2 = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uidString)
        
        if status2 == noErr, let uid = uidString {
            return uid as String
        }
        return nil
    }
    
    private func setupEngine() {
        // Setup EQ Bands
        // Band 0: Bass (Low Shelf) - Boost warmth/body
        let bass = eq.bands[0]
        bass.filterType = .lowShelf
        bass.frequency = 100.0
        bass.bypass = false
        
        // Band 1: Mid (Parametric) - Cut mud
        let mid = eq.bands[1]
        mid.filterType = .parametric
        mid.frequency = 400.0
        mid.bandwidth = 1.5
        mid.bypass = false
        
        // Band 2: Treble (High Shelf) - Boost presence/clarity
        let treble = eq.bands[2]
        treble.filterType = .highShelf
        treble.frequency = 3000.0
        treble.bypass = false
        
        updateEQ()
        
        engine.attach(player)
        engine.attach(eq)
        
        // Force Output to BlackHole 2ch
        configureOutputDevice()
        
        // Setup Capture Session
        captureSession.beginConfiguration()
        configureInputDevice(isInitialSetup: true)
        
        if captureSession.canAddOutput(captureOutput) {
            captureSession.addOutput(captureOutput)
        }
        
        // Request a standard format: 48kHz, Stereo, Float32, Non-Interleaved
        // This matches what AVAudioEngine usually likes.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        captureOutput.audioSettings = settings
        captureOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        captureSession.commitConfiguration()
        
        // Connect nodes immediately with the expected format
        if let format = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2) {
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        }
    }
    
    func resetToDefaults() {
        masterGain = 6.0
        bassGain = 5.0
        midGain = -3.0
        trebleGain = 4.0
    }
    
    private func updateEQ() {
        eq.globalGain = masterGain
        eq.bands[0].gain = bassGain
        eq.bands[1].gain = midGain
        eq.bands[2].gain = trebleGain
    }
    
    func start() {
        userIntentRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startSession()
                    } else {
                        self?.errorMessage = "Microphone permission denied."
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone permission denied. Please enable it in System Settings."
        @unknown default:
            errorMessage = "Unknown permission status."
        }
    }
    
    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Ensure output is set to BlackHole before starting
            self.configureOutputDevice()
            
            self.captureSession.startRunning()
            
            // Start audio engine
            do {
                if !self.engine.isRunning {
                    try self.engine.start()
                }
                self.player.play()
                
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error starting engine: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }
    
    func stop() {
        userIntentRunning = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            self?.engine.stop()
            self?.player.stop()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
    
    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = makePCMBuffer(from: sampleBuffer) else { return }
        player.scheduleBuffer(buffer)
    }
    
    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return nil }
        
        // Create AVAudioFormat from ASBD
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(CMSampleBufferGetNumSamples(sampleBuffer))) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        
        let audioBufferList = buffer.mutableAudioBufferList
        
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(buffer.frameLength),
            into: audioBufferList
        )
        
        if status != noErr { return nil }
        
        return buffer
    }
    
    private func configureOutputDevice() {
        let deviceName = "BlackHole 2ch"
        guard let deviceID = findDeviceID(byName: deviceName) else {
            print("⚠️ \(deviceName) not found. Using system default.")
            DispatchQueue.main.async { self.isBlackHoleFound = false }
            return
        }
        
        DispatchQueue.main.async { self.isBlackHoleFound = true }
        
        let outputUnit = engine.outputNode.audioUnit
        
        // Check if already set to avoid unnecessary resets
        var currentID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioUnitGetProperty(outputUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &currentID, &size)
        if currentID == deviceID {
            print("✅ Output already configured to \(deviceName)")
            return
        }
        
        var id = deviceID
        let error = AudioUnitSetProperty(
            outputUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if error != noErr {
            print("❌ Failed to set output device: \(error)")
        } else {
            print("✅ Output configured to \(deviceName)")
        }
    }

    private func findDeviceID(byName name: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let status2 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status2 == noErr else { return nil }
        
        for id in deviceIDs {
            var nameSize = UInt32(256)
            var deviceName = [CChar](repeating: 0, count: Int(nameSize))
            var nameProperty = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let status3 = AudioObjectGetPropertyData(id, &nameProperty, 0, nil, &nameSize, &deviceName)
            if status3 == noErr {
                let nameStr = String(cString: deviceName)
                if nameStr == name {
                    return id
                }
            }
        }
        return nil
    }
    
    private func configureInputDevice(isInitialSetup: Bool = false) {
        // If running, we need to stop session to reconfigure inputs safely
        let wasRunning = captureSession.isRunning
        if wasRunning && !isInitialSetup {
            captureSession.stopRunning()
        }
        
        captureSession.beginConfiguration()
        
        // Remove existing inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        
        // Find selected device
        guard let device = availableMicrophones.first(where: { $0.uniqueID == selectedMicrophoneID }) else {
            print("⚠️ Selected microphone not found in available list.")
            captureSession.commitConfiguration()
            if wasRunning && !isInitialSetup { captureSession.startRunning() }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                print("✅ Input configured to: \(device.localizedName)")
            } else {
                errorMessage = "Could not add microphone input."
                print("❌ Could not add input for: \(device.localizedName)")
            }
        } catch {
            errorMessage = "Error setting microphone: \(error.localizedDescription)"
            print("❌ Error creating input: \(error)")
        }
        
        captureSession.commitConfiguration()
        
        if wasRunning && !isInitialSetup {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
}
