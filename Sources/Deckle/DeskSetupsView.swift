import SwiftUI

struct DeskSetupsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isNaming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Desk setups").font(.system(size: 15, weight: .medium, design: .serif))
                Spacer()
                Button(isNaming ? "Cancel" : "Save current…") {
                    isNaming.toggle()
                    name = ""
                    nameFocused = isNaming
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(StudioStyle.rust)
                .disabled(state.deskSetups.count >= 8 || state.previewPaper != nil)
            }
            if isNaming {
                HStack {
                    TextField("Name this setup", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if state.deskSetups.isEmpty {
                Text("Save a paper, intensity, grain and matte combination for your next session.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(state.deskSetups) { setup in
                        let available = state.paperExists(id: setup.textureID)
                        let selected = state.matches(setup)
                        Button { state.apply(setup) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "bookmark")
                                    Spacer(minLength: 0)
                                    Text("\(Int(setup.intensity * 100))%")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                                .foregroundStyle(selected ? StudioStyle.rust : .secondary)
                                Text(setup.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(available ? "Paper + finish" : "Paper missing")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? StudioStyle.rust.opacity(0.08) : Color.primary.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? StudioStyle.rust.opacity(0.55) : Color.primary.opacity(0.08)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available || state.previewPaper != nil)
                        .help(available ? "Apply \(setup.name): paper, intensity, grain and matte" : "The paper used by this setup was deleted")
                        .contextMenu {
                            Button("Remove setup", role: .destructive) {
                                state.deskSetups.removeAll { $0.id == setup.id }
                            }
                        }
                    }
                }
            }
            if state.previewPaper != nil {
                Text("Finish your Paper Mill preview to use desk setups.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if state.deskSetups.count >= 8 {
                Text("8 setups saved. Right-click a setup to remove it.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        if state.saveDeskSetup(name: name) { isNaming = false; name = "" }
    }
}
