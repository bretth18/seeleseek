import SeeleseekCore

extension User {
    var statusIcon: String {
        switch status {
        case .offline: "circle.slash"
        case .away: "moon.fill"
        case .online: "circle.fill"
        }
    }
}
