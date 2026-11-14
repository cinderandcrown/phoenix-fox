// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Legal publisher identity for About / Privacy screens and mailto links.
// Publisher is Cinder and Crown LLC (Nicholas's decision, Nov 2026).

import Foundation

enum PublisherIdentity {
    static let legalName = "Cinder and Crown LLC"
    static let privacyEmail = "privacy@cinderandcrown.com"
    static let privacyMailto = URL(string: "mailto:privacy@cinderandcrown.com")!

    static let independentAppLine =
        "Phoenix Fox is published by \(legalName). It is an independent app and is not made by Meta, Ray-Ban, Oakley, OpenAI, xAI, Google, or Marvel."
}
