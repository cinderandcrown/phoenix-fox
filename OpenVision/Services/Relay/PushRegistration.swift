// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// Which relay holds this phone's push token, so the token is sent when it is needed and
/// not more often.
///
/// Apple hands over the token at launch. On a first run that is before the owner has typed
/// the relay token, so there is nowhere to send it yet. It is kept here, in memory only,
/// and sent once a relay is saved. A changed token or a changed relay sends it again.
/// Apple gives the token again on every launch, so nothing is written to disk.
struct PushRegistration: Equatable {
    struct Send: Equatable {
        var token: String
        var endpoint: RelayEndpoint
    }

    private(set) var token: String?
    private var accepted: Send?

    /// Records the token Apple gave this launch.
    mutating func received(token: String) {
        self.token = token
    }

    /// What still has to be sent, if anything.
    func pending(for endpoint: RelayEndpoint?) -> Send? {
        guard let token, let endpoint else { return nil }
        let send = Send(token: token, endpoint: endpoint)
        return send == accepted ? nil : send
    }

    /// Records that the relay took it.
    mutating func accepted(_ send: Send) {
        accepted = send
    }
}
