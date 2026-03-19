import SwiftUI
import Charts

struct HistoryView: View {
    @State private var historyData: HistoryResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDays = 14
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadHistory() }
                        }
                    }
                } else if let data = historyData {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Days selector
                            DaysSelectorView(selectedDays: $selectedDays)
                                .onChange(of: selectedDays) { _, _ in
                                    Task { await loadHistory() }
                                }
                            
                            // Calorie trend chart
                            CalorieTrendChart(trends: data.trends)
                            
                            // Top foods section
                            TopFoodsSection(topFoods: data.topFoods)
                            
                            // Meals by day
                            MealsByDaySection(groupedMeals: data.groupedMeals)
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView {
                        Label("No History", systemImage: "chart.bar")
                    } description: {
                        Text("Start logging meals to see your history")
                    }
                }
            }
            .navigationTitle("History")
            .refreshable {
                await loadHistory()
            }
            .task {
                await loadHistory()
            }
        }
    }
    
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            historyData = try await APIClient.shared.history(days: selectedDays)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Days Selector

struct DaysSelectorView: View {
    @Binding var selectedDays: Int
    
    private let options = [7, 14, 30]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.self) { days in
                Button {
                    selectedDays = days
                } label: {
                    Text("\(days) days")
                        .font(.subheadline)
                        .fontWeight(selectedDays == days ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedDays == days ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(selectedDays == days ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Calorie Trend Chart

struct CalorieTrendChart: View {
    let trends: [[String: AnyCodableValue]]
    
    private var chartData: [TrendDataPoint] {
        trends.compactMap { dict -> TrendDataPoint? in
            guard let dateValue = dict["date"],
                  let caloriesValue = dict["calories"] else { return nil }
            
            let dateString: String
            switch dateValue {
            case .string(let s): dateString = s
            default: return nil
            }
            
            let calories: Double
            switch caloriesValue {
            case .double(let d): calories = d
            case .int(let i): calories = Double(i)
            default: return nil
            }
            
            // Parse date
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: dateString) else { return nil }
            
            // Also get protein, carbs, fat
            var protein = 0.0
            var carbs = 0.0
            var fat = 0.0
            
            if let pVal = dict["protein_g"] {
                switch pVal {
                case .double(let d): protein = d
                case .int(let i): protein = Double(i)
                default: break
                }
            }
            
            if let cVal = dict["carbs_g"] {
                switch cVal {
                case .double(let d): carbs = d
                case .int(let i): carbs = Double(i)
                default: break
                }
            }
            
            if let fVal = dict["fat_g"] {
                switch fVal {
                case .double(let d): fat = d
                case .int(let i): fat = Double(i)
                default: break
                }
            }
            
            return TrendDataPoint(date: date, calories: calories, protein: protein, carbs: carbs, fat: fat)
        }.sorted { $0.date < $1.date }
    }
    
    private var averageCalories: Double {
        guard !chartData.isEmpty else { return 0 }
        return chartData.reduce(0) { $0 + $1.calories } / Double(chartData.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calorie Trend")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Avg: \(Int(averageCalories))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if chartData.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(chartData) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(4)
                    
                    RuleMark(y: .value("Average", averageCalories))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(.secondary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: chartData.count > 14 ? 7 : 2)) { value in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

// MARK: - Top Foods Section

struct TopFoodsSection: View {
    let topFoods: [[String: AnyCodableValue]]
    
    private var parsedFoods: [TopFoodItem] {
        topFoods.prefix(5).compactMap { dict -> TopFoodItem? in
            guard let nameValue = dict["canonical_name"],
                  let countValue = dict["count"],
                  let caloriesValue = dict["total_calories"] else { return nil }
            
            let name: String
            switch nameValue {
            case .string(let s): name = s
            default: return nil
            }
            
            let count: Int
            switch countValue {
            case .int(let i): count = i
            case .double(let d): count = Int(d)
            default: return nil
            }
            
            let calories: Double
            switch caloriesValue {
            case .double(let d): calories = d
            case .int(let i): calories = Double(i)
            default: return nil
            }
            
            return TopFoodItem(name: name, count: count, totalCalories: calories)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Foods")
                .font(.headline)
            
            if parsedFoods.isEmpty {
                Text("No food data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(parsedFoods.enumerated()), id: \.element.name) { index, food in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(rankColor(for: index))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name.capitalized)
                                .font(.subheadline)
                            Text("\(food.count) time\(food.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(food.totalCalories)) cal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if index < parsedFoods.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return .yellow
        case 1: return .gray
        case 2: return .orange
        default: return .secondary
        }
    }
}

struct TopFoodItem {
    let name: String
    let count: Int
    let totalCalories: Double
}

// MARK: - Meals By Day Section

struct MealsByDaySection: View {
    let groupedMeals: [String: [MealRecord]]
    
    private var sortedDates: [String] {
        groupedMeals.keys.sorted().reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meals by Day")
                .font(.headline)
            
            if sortedDates.isEmpty {
                Text("No meals logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedDates, id: \.self) { dateString in
                    DayMealsCard(dateString: dateString, meals: groupedMeals[dateString] ?? [])
                }
            }
        }
    }
}

struct DayMealsCard: View {
    let dateString: String
    let meals: [MealRecord]
    
    @State private var isExpanded = false
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: date)
    }
    
    private var totalCalories: Double {
        meals.reduce(0) { $0 + $1.totalCalories }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(meals.count) meal\(meals.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(Int(totalCalories)) cal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                ForEach(meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.mealName)
                                .font(.subheadline)
                            Text(formatTime(meal.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(meal.totalCalories)) cal")
                                .font(.caption)
                            HStack(spacing: 4) {
                                Text("P:\(Int(meal.totalProteinG))")
                                Text("C:\(Int(meal.totalCarbsG))")
                                Text("F:\(Int(meal.totalFatG))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    if meal.id != meals.last?.id {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return "" }
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }
}

#Preview {
    HistoryView()
}
