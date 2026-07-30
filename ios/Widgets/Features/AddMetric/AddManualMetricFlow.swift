import SwiftUI
import SwiftData
import WidgetsShared

struct AddManualMetricFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appContainer: AppContainerHolder

    let kind: MetricKind
    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var color: PaletteName = .githubGreen

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Sales calls, Deep focus, …", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(PaletteName.allCases) { palette in
                            Button {
                                color = palette
                            } label: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Palette.resolve(palette).l3)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if color == palette {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.headline)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New \(kind.displayName.lowercased()) metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    create()
                } label: {
                    Text("Add metric")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Palette.githubGreen.l3)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
    }

    private func create() {
        let metric = PersistedMetric(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            color: color
        )
        context.insert(metric)
        try? context.save()
        SyncCoordinator(context: context, integrations: appContainer.container).rebuildManualOnly()
        onComplete()
    }
}
