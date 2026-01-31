import SwiftUI

struct SnippetsTab: View {
    @ObservedObject var appState: AppState
    @State private var showingAddSnippet = false
    @State private var newTrigger = ""
    @State private var newExpansion = ""
    
    var body: some View {
        VStack(spacing: 12) {
            Toggle("Enable Snippets", isOn: $appState.useSnippets)
                .toggleStyle(.switch)
                .padding(.horizontal)
            
            Divider()
            
            if appState.snippetStore.snippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No snippets yet")
                        .font(.headline)
                    Text("Add your first trigger phrase below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(appState.snippetStore.snippets) { snippet in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.trigger)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(snippet.expansion)
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if let index = appState.snippetStore.snippets.firstIndex(where: { $0.id == snippet.id }) {
                                    appState.snippetStore.deleteSnippet(at: IndexSet(integer: index))
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        appState.snippetStore.deleteSnippet(at: indexSet)
                    }
                }
                .listStyle(.plain)
                .frame(height: 200) // Fixed height to prevent vertical expansion
            }
            
            Divider()
            
            VStack(spacing: 8) {
                HStack {
                    TextField("Trigger (e.g. intro email)", text: $newTrigger)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    
                    Button(action: addSnippet) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTrigger.isEmpty || newExpansion.isEmpty)
                }
                
                TextEditor(text: $newExpansion)
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if newExpansion.isEmpty {
                                Text("Expansion text here...")
                                    .font(.caption)
                                    .foregroundStyle(.placeholder)
                                    .padding(.leading, 4)
                                    .padding(.top, 8)
                            }
                        },
                        alignment: .topLeading
                    )
            }
            .padding(.horizontal)
        }
    }
    
    private func addSnippet() {
        appState.snippetStore.addSnippet(trigger: newTrigger, expansion: newExpansion)
        newTrigger = ""
        newExpansion = ""
    }
}
