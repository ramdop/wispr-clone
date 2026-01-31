import SwiftUI

struct DictionaryTab: View {
    @ObservedObject var appState: AppState
    @State private var newWord: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Custom Vocabulary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)


            // Text("Path: \(appState.learnedDictionaryStore.entriesUrl.path)")
            //    .font(.caption2).foregroundStyle(.red)
            
            Text("Add names, acronyms, or specific words to help Wispr understand you better.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            Divider()
            
            if appState.customVocabularyStore.words.isEmpty && appState.learnedDictionaryStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Dictionary is empty")
                        .font(.subheadline)
                    Text("Add your first word below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    // Section 1: Custom Vocabulary
                    if !appState.customVocabularyStore.words.isEmpty {
                        Section("Custom Vocabulary") {
                            ForEach(appState.customVocabularyStore.words, id: \.self) { word in
                                HStack {
                                    Text(word)
                                        .font(.body)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        appState.customVocabularyStore.removeWord(word)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                appState.customVocabularyStore.deleteWords(at: indexSet)
                            }
                        }
                    }
                    
                    // Section 2: Learned Corrections
                    if !appState.learnedDictionaryStore.entries.isEmpty {
                        Section("Learned Corrections") {
                            ForEach(appState.learnedDictionaryStore.entries) { entry in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(entry.canonical)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(entry.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(4)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    
                                    Text(entry.aliases.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        appState.learnedDictionaryStore.removeEntry(entry)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                // Map indexSet to entries and delete
                                let entriesStart = 0 // Assuming standalone section behavior in ForEach
                                indexSet.forEach { index in
                                    if index < appState.learnedDictionaryStore.entries.count {
                                        let entry = appState.learnedDictionaryStore.entries[index]
                                        appState.learnedDictionaryStore.removeEntry(entry)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: 200)
            }
            
            Divider()
            
            HStack {
                TextField("Enter new word (e.g. Aadhar)", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit {
                        addWord()
                    }
                
                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    private func addWord() {
        guard !newWord.isEmpty else { return }
        appState.customVocabularyStore.addWord(newWord)
        newWord = ""
    }
}
