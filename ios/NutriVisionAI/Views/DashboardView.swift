import SwiftUI

struct DashboardView: View {
    @State private var dashboardData: DashboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMeal: MealRecord?
    
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
                        // Calorie Summary Card
                        CalorieSummaryCard(summary: data.summary)
                        
                        // Macro Progress
                        MacroProgressSection(summary: data.summary)
                        
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
            .navigationTitle("NutriVision")
            .refreshable {
                await loadDashboard()
            }
            .task {
                await loadDashboard()
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
        do {
            dashboardData = try await APIClient.shared.dashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func deleteMeal(_ meal: MealRecord) {
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

// MARK: - Calorie Summary Card

struct CalorieSummaryCard: View {
    let summary: DashboardSummary
    
    private var progress: Double {
        guard summary.calorieGoal > 0 else { return 0 }
        return min(summary.calories / Double(summary.calorieGoal), 1.0)
    }
    
    private var progressColor: Color {
        if progress >= 1.0 { return .red }
        if progress >= 0.9 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Today's Calories")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 20)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progressColor.gradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.6), value: progress)
                
                // Center content
                VStack(spacing: 4) {
                    Text("\(Int(summary.calories))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    
                    Text("of \(summary.calorieGoal) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if summary.remainingCalories > 0 {
                        Text("\(Int(summary.remainingCalories)) remaining")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(Int(-summary.remainingCalories)) over")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(width: 200, height: 200)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Macro Progress Section

struct MacroProgressSection: View {
    let summary: DashboardSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Macros")
                .font(.headline)
            
            VStack(spacing: 12) {
                MacroProgressBar(
                    label: "Protein",
                    value: summary.proteinG,
                    goal: Double(summary.macroGoals.proteinG),
                    color: .blue,
                    unit: "g"
                )
                
                MacroProgressBar(
                    label: "Carbs",
                    value: summary.carbsG,
                    goal: Double(summary.macroGoals.carbsG),
                    color: .orange,
                    unit: "g"
                )
                
                MacroProgressBar(
                    label: "Fat",
                    value: summary.fatG,
                    goal: Double(summary.macroGoals.fatG),
                    color: .purple,
                    unit: "g"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MacroProgressBar: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color
    let unit: String
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(value))/\(Int(goal))\(unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(duration: 0.4), value: progress)
                }
            }
            .frame(height: 8)
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
                Spacer()
                if !meals.isEmpty {
                    Text("\(meals.count) today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MealRowCard: View {
    let meal: MealRecord
    
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
                AsyncImage(url: URL(string: "\(APIClient.shared.baseURL)\(imagePath)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.mealName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(meal.totalCalories))")
                    .font(.body)
                    .fontWeight(.semibold)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
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
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardView()
}
