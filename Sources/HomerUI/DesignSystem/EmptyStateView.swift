import SwiftUI

package struct EmptyStateView: View {
	package let title: String
	package let systemImage: String
	package let description: String

	package init(title: String, systemImage: String, description: String) {
		self.title = title
		self.systemImage = systemImage
		self.description = description
	}

	package var body: some View {
		VStack {
			Spacer()
			ContentUnavailableView(
				title,
				systemImage: systemImage,
				description: Text(description)
			)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
