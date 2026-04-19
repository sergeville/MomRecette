import SwiftUI

struct GenerateRecipeImageButton: View {
    let action: () -> Void

    var body: some View {
        Button("Generate Image", action: action)
            .fontWeight(.semibold)
    }
}

#if DEBUG
#Preview {
    GenerateRecipeImageButton(action: {})
}
#endif
