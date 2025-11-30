//
//  ContentView.swift
//  micboost
//
//  Created by ahmet on 28/11/2025.
//

import SwiftUI
internal import AVFoundation

struct ContentView: View {
    @ObservedObject var engine: MicEQEngine
    
    var body: some View {
        VStack(spacing: 20) {
            /* Image(systemName: engine.isRunning ? "mic.fill" : "mic.slash.fill")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(engine.isRunning ? .green : .red) */
            
            /* Text("Mic Boost EQ")
                .font(.largeTitle)
                .fontWeight(.bold) */
            
            if let error = engine.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            if !engine.isBlackHoleFound {
                Text("⚠️ BlackHole 2ch not found!\nAudio will play through speakers.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                if engine.isRunning {
                    engine.stop()
                } else {
                    engine.start()
                }
            }) {
                Text(engine.isRunning ? "Stop Engine" : "Start Engine")
                    .font(.headline)
                    .padding()
                    .frame(width: 200)
                    // .background(engine.isRunning ? Color.red : Color.blue)
                    // .foregroundColor(.white)
                    // .cornerRadius(10)
            }
            .buttonStyle(.automatic)
            
            Picker("Microphone", selection: $engine.selectedMicrophoneID) {
                ForEach(engine.availableMicrophones, id: \.uniqueID) { mic in
                    Text(mic.localizedName).tag(mic.uniqueID)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            
            Divider()
            
            VStack(spacing: 15) {
                EQSlider(label: "Gain", value: $engine.masterGain)
                Divider()
                EQSlider(label: "Bass", value: $engine.bassGain)
                EQSlider(label: "Mid", value: $engine.midGain)
                EQSlider(label: "Treble", value: $engine.trebleGain)
                
                Button("Reset to Default") {
                    engine.resetToDefaults()
                }
                .font(.caption)
                .padding(.top, 5)
            }
            .padding(.horizontal)
            
            Divider()
            
            /* VStack(alignment: .leading, spacing: 10) {
                Text("Instructions:")
                    .font(.headline)
                Text("1. In Discord/OBS/etc, set Input to **BlackHole 2ch**")
                Text("2. (Optional) System Output can remain as Speakers")
            .font(.caption)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Divider()
            } */
            
            Button("Quit Mic Boost") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
        .background(.ultraThinMaterial)
        .background(WindowAccessor())
    }
}

struct EQSlider: View {
    let label: String
    @Binding var value: Float
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 50, alignment: .leading)
            Slider(value: $value, in: -12...12, step: 0.5)
            Text("\(value, specifier: "%.1f") dB")
                .frame(width: 60, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isOpaque = false
            view.window?.backgroundColor = .clear
            // Optional: remove title bar if desired, but might break MenuBarExtra behavior
            // view.window?.styleMask.insert(.fullSizeContentView)
            // view.window?.titlebarAppearsTransparent = true
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView(engine: MicEQEngine())
}
