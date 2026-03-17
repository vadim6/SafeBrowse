import SwiftUI

struct BlocklistsView: View {
    @EnvironmentObject var state: AppState

    @State private var showAddSource = false
    @State private var newBlockEntry = ""
    @State private var newAllowEntry = ""

    var body: some View {
        HSplitView {
            // ── Column 1: URL-based blocklist sources ──────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Blocklist Sources")
                        .font(.headline)
                    Spacer()
                    if state.isBlocking {
                        Label("Pause to edit", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { @MainActor in state.updateBlocklists() }
                        } label: {
                            if state.isUpdatingBlocklists {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Update All", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(state.isUpdatingBlocklists)
                    }
                }
                .padding()

                Divider()

                List {
                    ForEach($state.blocklists) { $source in
                        BlocklistRow(source: $source)
                            .contextMenu {
                                Button(role: .destructive) {
                                    state.removeBlocklist(id: source.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .disabled(state.isBlocking)
                            }
                    }
                    .onDelete { idx in
                        guard !state.isBlocking else { return }
                        for i in idx { state.removeBlocklist(id: state.blocklists[i].id) }
                    }
                }

                if let error = state.updateError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                Divider()

                Button("Add Custom Source…") { showAddSource = true }
                    .padding()
            }
            .frame(minWidth: 300)

            // ── Column 2: Custom blocked domains ──────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                Text("Custom Blocked Domains")
                    .font(.headline)
                    .padding()

                Divider()

                List {
                    ForEach(state.customBlocklist, id: \.self) { domain in
                        HStack {
                            Text(domain).font(.body.monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                guard !state.isBlocking else { return }
                                state.removeCustomBlocklistEntry(domain)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(state.isBlocking ? Color.secondary : Color.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("example.com", text: $newBlockEntry)
                        .textFieldStyle(.roundedBorder)
                    Button("Block") {
                        state.addCustomBlocklistEntry(newBlockEntry)
                        newBlockEntry = ""
                    }
                    .disabled(newBlockEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .frame(minWidth: 200)

            // ── Column 3: Allowlist ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Allowlist (never blocked)")
                        .font(.headline)
                    Spacer()
                    if state.isBlocking {
                        Label("Pause to edit", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                List {
                    ForEach(state.allowlist, id: \.self) { domain in
                        HStack {
                            Text(domain).font(.body.monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                state.removeAllowlistEntry(domain)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("example.com", text: $newAllowEntry)
                        .textFieldStyle(.roundedBorder)
                    Button("Allow") {
                        state.addAllowlistEntry(newAllowEntry)
                        newAllowEntry = ""
                    }
                    .disabled(newAllowEntry.trimmingCharacters(in: .whitespaces).isEmpty || state.isBlocking)
                }
                .padding()
            }
            .frame(minWidth: 200)
        }
        .sheet(isPresented: $showAddSource) {
            AddSourceSheet(isPresented: $showAddSource)
                .environmentObject(state)
        }
    }
}

// MARK: - Blocklist row

private struct BlocklistRow: View {
    @Binding var source: BlocklistSource
    @EnvironmentObject var state: AppState
    @State private var isHovered = false
    @State private var showEdit = false
    @State private var editName = ""
    @State private var editURL = ""

    var body: some View {
        HStack {
            Toggle("", isOn: $source.isEnabled)
                .labelsHidden()
                .disabled(state.isBlocking)
                .onChange(of: source.isEnabled) { _ in
                    Task { @MainActor in state.updateBlocklists() }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.body)
                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if source.domainCount > 0 {
                    Text("\(source.domainCount.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let updated = source.lastUpdated {
                    Text(updated, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                editName = source.name
                editURL = source.url
                showEdit = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered && !state.isBlocking ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            Button(role: .destructive) {
                state.removeBlocklist(id: source.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(state.isBlocking)
            .opacity(isHovered && !state.isBlocking ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showEdit) {
            EditSourceSheet(isPresented: $showEdit, source: $source)
                .environmentObject(state)
        }
    }
}

// MARK: - Add source sheet

private struct AddSourceSheet: View {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var url  = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Blocklist")
                .font(.headline)

            TextField("Name (e.g. AdGuard DNS)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("URL (hosts or plain domain list)", text: $url)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Add") {
                    let source = BlocklistSource(name: name, url: url)
                    state.blocklists.append(source)
                    state.updateBlocklists()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Edit source sheet

private struct EditSourceSheet: View {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    @Binding var source: BlocklistSource
    @State private var name: String = ""
    @State private var url: String  = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Blocklist Source")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: $url)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    source.name = name
                    source.url  = url
                    state.updateBlocklists()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            name = source.name
            url  = source.url
        }
    }
}
