// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(Config.appVersion) (\(Config.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                Text("Phoenix Fox is an independent app. It is not made by Meta, Ray-Ban, Oakley, OpenAI, xAI, Google, or Marvel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Privacy Policy", destination: StoreCatalog.privacyURL)
                Link("Terms of Use", destination: StoreCatalog.termsURL)
                NavigationLink("Licenses / Acknowledgements") {
                    LicensesView()
                }
            } header: {
                Text("Legal")
            }

            Section {
                Link("Contact", destination: URL(string: "mailto:privacy@cinderandcrown.com")!)
            } footer: {
                Text("Say Jarvis to wake the glasses assistant.")
            }
        }
        .navigationTitle("About")
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.loadBundled("NOTICE") ?? Self.noticeFallback)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Divider()
                Text(Self.loadBundled("THIRD_PARTY_NOTICES") ?? Self.thirdPartyFallback)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Licenses")
    }

    private static func loadBundled(_ name: String) -> String? {
        for ext in ["", "md", "txt"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext),
               let text = try? String(contentsOf: url, encoding: .utf8),
               !text.isEmpty {
                return text
            }
        }
        // Repo-root copies used when not yet copied into the app bundle.
        let roots = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
        ]
        for root in roots {
            for candidate in ["\(name).md", name, "NOTICE"] {
                let url = root.appendingPathComponent(candidate)
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private static let noticeFallback = """
    Phoenix Fox
    Copyright 2026 Cinder and Crown LLC

    Licensed under the Apache License, Version 2.0.
    """

    private static let thirdPartyFallback = """
    See THIRD_PARTY_NOTICES.md in the Phoenix Fox repository for OpenVision (MIT) and other notices.
    """
}

#Preview {
    NavigationStack { AboutView() }
}
