import UIKit

extension UINavigationItem {
    /// Inserts/replaces/removes a right bar button identified by `tag`, leaving
    /// buttons owned by other bridge components untouched. Lets navbar-buttons
    /// (overflow) and notification-count (bell) coexist on the same nav bar.
    func setBridgeRightBarButton(_ item: UIBarButtonItem?, tag: Int) {
        var items = rightBarButtonItems ?? []
        items.removeAll { $0.tag == tag }
        if let item {
            item.tag = tag
            items.append(item)
        }
        rightBarButtonItems = items
    }
}
