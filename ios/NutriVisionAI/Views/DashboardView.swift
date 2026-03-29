import SwiftUI

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dashboardData: DashboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMeal: MealRecord?
    @State private var lastLoadedDate: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadDashboard() }
                        }
                    }
                } else if let data = dashboardData {
                    VStack(spacing: 24) {
                        // Compact Calorie + Macro Card
                        CompactDashboardCard(summary: data.summary)

                        // AI Meal Suggestions
                        MealSuggestionsView(
                            summary: data.summary,
                            recentMeals: data.recentMeals,
                            settings: nil
                        )

                        // Recent Meals
                        RecentMealsSection(
                            meals: data.recentMeals,
                            onDelete: deleteMeal,
                            onSelect: { meal in selectedMeal = meal }
                        )
                    }
                    .padding()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("NutriVision")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .refreshable {
                await loadDashboard()
            }
            .task {
                lastLoadedDate = todayString()
                await loadDashboard()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    let today = todayString()
                    if today != lastLoadedDate {
                        lastLoadedDate = today
                        Task { await loadDashboard() }
                    }
                }
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailSheet(meal: meal, onDelete: {
                    Task { await loadDashboard() }
                })
            }
        }
    }

    private func loadDashboard() async {
        isLoading = true
        errorMessage = nil

        if FoodAnalysisService.shared.isCloudMode {
            let summary = LocalMealStore.shared.todaySummary()
            let meals = LocalMealStore.shared.recentMeals()
            dashboardData = DashboardResponse(
                summary: summary,
                recentMeals: meals,
                user: UserInfo(id: 0, name: "Local", email: "")
            )
            isLoading = false
        } else {
            do {
                dashboardData = try await APIClient.shared.dashboard()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func deleteMeal(_ meal: MealRecord) {
        if FoodAnalysisService.shared.isCloudMode {
            LocalMealStore.shared.deleteMeal(id: meal.id)
            Task { await loadDashboard() }
        } else {
            Task {
                do {
                    try await APIClient.shared.deleteMeal(id: meal.id)
                    await loadDashboard()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Compact Dashboard Card

struct CompactDashboardCard: View {
    let summary: DashboardSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard summary.calorieGoal > 0 else { return 0 }
        return min(summary.calories / Double(summary.calorieGoal), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Compact calorie ring
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .motionSafeAnimation(.spring(duration: 0.6), value: progress)

                VStack(spacing: 1) {
                    Text("\(Int(summary.calories))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 90, height: 90)

            // Right side: calorie info + macro bars
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("of \(summary.calorieGoal) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    if summary.remainingCalories > 0 {
                        Text("\(Int(summary.remainingCalories)) remaining")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.positive)
                    } else {
                        Text("\(Int(-summary.remainingCalories)) over")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.destructive)
                    }
                }

                CompactMacroBar(label: "P", value: summary.proteinG, goal: Double(summary.macroGoals.proteinG), gradient: Theme.proteinGradient)
                CompactMacroBar(label: "C", value: summary.carbsG, goal: Double(summary.macroGoals.carbsG), gradient: Theme.carbsGradient)
                CompactMacroBar(label: "F", value: summary.fatG, goal: Double(summary.macroGoals.fatG), gradient: Theme.fatGradient)
            }
        }
        .padding()
        .themedCard(glow: true)
    }
}

struct CompactMacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    let gradient: LinearGradient

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 12)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.cardBorder)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradient)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 6)

            Text("\(Int(value))/\(Int(goal))g")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

// MARK: - Recent Meals Section

struct RecentMealsSection: View {
    let meals: [MealRecord]
    let onDelete: (MealRecord) -> Void
    let onSelect: (MealRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Meals")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !meals.isEmpty {
                    Text("\(meals.count) today")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if meals.isEmpty {
                ContentUnavailableView {
                    Label("No Meals Yet", systemImage: "fork.knife")
                } description: {
                    Text("Scan or log your first meal to get started")
                }
                .frame(minHeight: 150)
            } else {
                ForEach(meals) { meal in
                    MealRowCard(meal: meal)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(meal) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(meal)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .padding()
        .themedCard()
    }
}

struct MealRowCard: View {
    let meal: MealRecord

    /// Load a locally-saved meal image by filename from Documents/MealImages/
    static func loadLocalMealImage(_ path: String) -> UIImage? {
        // If it's just a filename (not a URL path), look in local MealImages dir
        guard !path.hasPrefix("/"), !path.hasPrefix("http") else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("MealImages").appendingPathComponent(path)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private var formattedTime: String {
        // Parse ISO date and format to time
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: meal.createdAt) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        return meal.createdAt
    }

    var body: some View {
        HStack(spacing: 12) {
            // Meal image or placeholder
            if let imagePath = meal.imagePath, !imagePath.isEmpty {
                Group {
                    if let localImage = Self.loadLocalMealImage(imagePath) {
                        Image(uiImage: localImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if imagePath.hasPrefix("/") {
                        // Server-relative path (backend mode)
                        AsyncImage(url: URL(string: "\(APIClient.shared.baseURL)\(imagePath)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(Theme.textMuted)
                            default:
                                ProgressView()
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.thumbnailGradients[abs(meal.id.hashValue) % Theme.thumbnailGradients.count])
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(Theme.textMuted)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.mealName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(meal.totalCalories))")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.calorieValue)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Meal Detail Sheet

struct MealDetailSheet: View {
    let meal: MealRecord
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Meal Image
                    if let imagePath = meal.imagePath, !imagePath.isEmpty {
                        Group {
                            if let localImage = MealRowCard.loadLocalMealImage(imagePath) {
                                Image(uiImage: localImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else if imagePath.hasPrefix("/") {
                                AsyncImage(url: URL(string: "\(APIClient.shared.baseURL)\(imagePath)")) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    case .failure:
                                        EmptyView()
                                    default:
                                        ProgressView()
                                            .frame(height: 200)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 250)
                    }

                    // Nutrition Summary
                    VStack(spacing: 16) {
                        HStack(spacing: 20) {
                            NutritionStatView(value: Int(meal.totalCalories), label: "Calories", unit: "kcal")
                            Divider().frame(height: 40)
                            NutritionStatView(value: Int(meal.totalProteinG), label: "Protein", unit: "g")
                        }

                        Divider()

                        HStack(spacing: 20) {
                            NutritionStatView(value: Int(meal.totalCarbsG), label: "Carbs", unit: "g")
                            Divider().frame(height: 40)
                            NutritionStatView(value: Int(meal.totalFatG), label: "Fat", unit: "g")
                        }
                    }
                    .padding()
                    .themedCard()

                    // Delete Button
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Meal", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle(meal.mealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete Meal", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await APIClient.shared.deleteMeal(id: meal.id)
                        onDelete()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this meal?")
            }
        }
    }
}

struct NutritionStatView: View {
    let value: Int
    let label: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardView()
}
