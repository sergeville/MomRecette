import SwiftUI

// MARK: - Rolodex Deck (Card Carousel)

struct RolodexDeckView: View {
    @EnvironmentObject var store: RecipeStore
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var selectedRecipe: Recipe? = nil
    @State private var showDetail: Bool = false

    private let cardHeight: CGFloat = 420
    private let stackOffset: CGFloat = 12
    private let stackScale: CGFloat = 0.04

    var recipes: [Recipe] { store.filteredRecipes }

    var body: some View {
        VStack(spacing: 0) {
            if recipes.isEmpty {
                EmptyDeckView()
            } else {
                counterBar
                cardStack
                navButtons.padding(.top, 20)
            }
        }
        .onChange(of: store.filteredRecipes.count) { _ in
            currentIndex = 0
        }
        .sheet(isPresented: $showDetail) {
            if let recipe = selectedRecipe {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - Sub-Views

    private var counterBar: some View {
        HStack {
            Text("\(currentIndex + 1) / \(recipes.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            letterIndexView
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    private var cardStack: some View {
        ZStack {
            ForEach(stackIndices, id: \.self) { offset in
                cardView(offset: offset)
            }
        }
        .gesture(dragGesture)
        .onTapGesture {
            selectedRecipe = recipes[currentIndex]
            showDetail = true
        }
        .frame(height: cardHeight + CGFloat(stackIndices.count) * stackOffset + 20)
    }

    private func cardView(offset: Int) -> some View {
        let safeIdx = ((currentIndex + offset) % max(1, recipes.count) + recipes.count) % recipes.count
        let xOffset: CGFloat = offset == 0 ? dragOffset : 0
        let rotDeg: Double = offset == 0 ? Double(dragOffset) * 0.04 : 0
        let opac: Double = offset == 0 ? 1.0 : max(0.3, 1.0 - Double(offset) * 0.25)
        return RecipeCardView(recipe: recipes[safeIdx], isTop: offset == 0)
            .scaleEffect(1.0 - CGFloat(offset) * stackScale)
            .offset(x: xOffset, y: CGFloat(offset) * stackOffset)
            .zIndex(Double(10 - offset))
            .opacity(opac)
            .rotation3DEffect(.degrees(rotDeg), axis: (x: 0, y: 1, z: 0))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                isDragging = true
                dragOffset = v.translation.width
            }
            .onEnded { v in
                isDragging = false
                let threshold: CGFloat = 80
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    if v.translation.width < -threshold && currentIndex < recipes.count - 1 {
                        currentIndex += 1
                    } else if v.translation.width > threshold && currentIndex > 0 {
                        currentIndex -= 1
                    }
                    dragOffset = 0
                }
            }
    }

    private var navButtons: some View {
        HStack(spacing: 60) {
            Button {
                guard currentIndex > 0 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { currentIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(currentIndex > 0 ? Color.primary : Color.secondary.opacity(0.3))
            }
            .disabled(currentIndex <= 0)

            Button {
                selectedRecipe = recipes[currentIndex]
                showDetail = true
            } label: {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                guard currentIndex < recipes.count - 1 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { currentIndex += 1 }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(currentIndex < recipes.count - 1 ? Color.primary : Color.secondary.opacity(0.3))
            }
            .disabled(currentIndex >= recipes.count - 1)
        }
    }

    // MARK: - Helpers

    private var stackIndices: [Int] {
        var indices: [Int] = []
        let maxVisible = min(4, recipes.count)
        for i in 0..<maxVisible where currentIndex + i < recipes.count {
            indices.append(i)
        }
        return indices.reversed()
    }

    private var letterIndexView: some View {
        let letters = store.groupedByLetter.map { $0.0 }
        let current = recipes[safe: currentIndex]?.firstLetter
        return HStack(spacing: 3) {
            ForEach(letters, id: \.self) { letter in
                let firstIdx = store.filteredRecipes.firstIndex(where: { $0.firstLetter == letter }) ?? 0
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        currentIndex = firstIdx
                    }
                } label: {
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(current == letter ? Color.accentColor : Color.secondary)
                }
            }
        }
    }
}

// MARK: - Empty State

private struct EmptyDeckView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text("Aucune recette")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Ajoutez votre première recette\navec le bouton +")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    RolodexDeckView()
        .environmentObject(RecipeStore())
}
