import Domain
import SwiftUI
import UIKit

struct JobDetailView: View {
    @StateObject private var vm: JobDetailViewModel
    @State private var showsCamera = false
    @State private var image: UIImage?

    /// Builds the view model only when the screen opens, not for every row the list draws.
    init(vm: @autoclosure @escaping () -> JobDetailViewModel) { _vm = StateObject(wrappedValue: vm()) }

    var body: some View {
        Form {
            if let job = vm.job {
                Section {
                    Text(job.task)
                    Text("\(job.windowStart)–\(job.windowEnd)")
                }
                Section {
                    Button { showsCamera = true } label: { photoLabel }
                        .disabled(!vm.canTakePhoto)
                        .accessibilityLabel(vm.photo == nil ? "Take a photo" : "Photo taken")
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $vm.note)
                            .frame(minHeight: 120)
                            .disabled(job.completedAt != nil)
                            .accessibilityLabel("Note (optional)")
                        if vm.note.isEmpty {
                            Text("Note (optional)")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5) // lines up with the editor's own text inset
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                } footer: {
                    Text(vm.noteCounter)
                }
                Section {
                    if let statusLine = vm.statusLine {
                        Text(statusLine)
                    } else {
                        Button("Complete job") { Task { await vm.complete() } }
                            .disabled(!vm.canComplete)
                    }
                }
            }
        }
        .navigationTitle(vm.job?.address ?? "")
        .sheet(isPresented: $showsCamera) {
            CameraPicker { picked in
                // shortcut: encodes on the main thread, well under a second for a 12 MP photo; move it off if the pause shows.
                guard let jpeg = PhotoEncoder.jpeg(from: picked) else { return }
                Task { await vm.photoTaken(jpeg) }
            }
        }
        .onReceive(vm.$photo) { image = $0.flatMap(UIImage.init(data:)) } // decoded once, not on every keystroke
        .task { await vm.start() }
    }

    @ViewBuilder private var photoLabel: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Label("Take a photo", systemImage: "camera")
        }
    }
}
