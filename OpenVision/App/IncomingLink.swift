// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// What a URL that opened the app is for.
///
/// Phoenix Fox is opened by universal links on one domain. The domain's
/// apple-app-site-association file hands the app two path families, `/dat*` and `/app*`,
/// and this type accepts exactly those. Anything else is ignored rather than passed on.
enum IncomingLink: Equatable {
    /// The Meta AI app coming back from glasses registration or a permission prompt.
    case wearables(URL)
    /// A link into the app itself.
    case app(path: String)

    /// The universal-link domain. It must match the Associated Domains entitlement and the
    /// link saved in the Meta Wearables Developer Center.
    static let host = "phoenix-fox-links.cinderandcrown.workers.dev"

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == Self.host else { return nil }
        let path = url.path
        if path.hasPrefix("/dat") {
            self = .wearables(url)
        } else if path.hasPrefix("/app") {
            self = .app(path: path)
        } else {
            return nil
        }
    }
}
