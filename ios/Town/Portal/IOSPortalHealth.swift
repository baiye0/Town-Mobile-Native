import Foundation
import HealthKit

/// HealthKit deliberately hides read authorization. Never infer it from a completed
/// authorization request, sharingAuthorizationStatus, or an empty query result.
@MainActor protocol IOSPortalHealthAccess: AnyObject {
    var available: Bool { get }
    func authorize(_ categories: Set<String>) async throws
    func read(_ args: [String: Any]) async throws -> [String: Any]
}

@MainActor final class IOSPortalHealth: IOSPortalHealthAccess {
    struct Category: Identifiable {
        let id: String
        let title: String
        let type: HKSampleType
        let unit: HKUnit?
        let unitName: String?
        var scale: Double = 1
    }
    private static func quantity(_ id: String, _ title: String, _ type: HKQuantityTypeIdentifier, _ unit: HKUnit, _ unitName: String, scale: Double = 1) -> Category {
        Category(id: id, title: title, type: HKQuantityType(type), unit: unit, unitName: unitName, scale: scale)
    }
    static let categories: [Category] = [
        quantity("steps", "步数", .stepCount, .count(), "count"),
        Category(id: "sleep", title: "睡眠", type: HKCategoryType(.sleepAnalysis), unit: nil, unitName: nil),
        quantity("heart_rate", "心率", .heartRate, HKUnit.count().unitDivided(by: .minute()), "count/min"),
        quantity("body_mass", "体重", .bodyMass, .gramUnit(with: .kilo), "kg"),
        Category(id: "workouts", title: "锻炼", type: HKObjectType.workoutType(), unit: nil, unitName: nil),
        quantity("walking_running_distance", "步行与跑步距离", .distanceWalkingRunning, .meter(), "m"),
        quantity("cycling_distance", "骑行距离", .distanceCycling, .meter(), "m"),
        quantity("swimming_distance", "游泳距离", .distanceSwimming, .meter(), "m"),
        quantity("flights_climbed", "爬楼层数", .flightsClimbed, .count(), "count"),
        quantity("active_energy", "活动能量", .activeEnergyBurned, .kilocalorie(), "kcal"),
        quantity("resting_energy", "静息能量", .basalEnergyBurned, .kilocalorie(), "kcal"),
        quantity("exercise_time", "锻炼时间", .appleExerciseTime, .minute(), "min"),
        quantity("stand_time", "站立时间", .appleStandTime, .minute(), "min"),
        quantity("resting_heart_rate", "静息心率", .restingHeartRate, HKUnit.count().unitDivided(by: .minute()), "count/min"),
        quantity("heart_rate_variability", "心率变异性", .heartRateVariabilitySDNN, .secondUnit(with: .milli), "ms"),
        quantity("oxygen_saturation", "血氧饱和度", .oxygenSaturation, .percent(), "%", scale: 100),
        quantity("respiratory_rate", "呼吸频率", .respiratoryRate, HKUnit.count().unitDivided(by: .minute()), "count/min"),
        quantity("vo2_max", "有氧适能", .vo2Max, HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), "mL/kg/min"),
        quantity("height", "身高", .height, .meterUnit(with: .centi), "cm"),
        quantity("body_mass_index", "身体质量指数", .bodyMassIndex, .count(), "count"),
        quantity("body_fat", "体脂率", .bodyFatPercentage, .percent(), "%", scale: 100),
        quantity("lean_body_mass", "去脂体重", .leanBodyMass, .gramUnit(with: .kilo), "kg"),
        quantity("waist_circumference", "腰围", .waistCircumference, .meterUnit(with: .centi), "cm"),
        quantity("body_temperature", "体温", .bodyTemperature, .degreeCelsius(), "degC"),
        quantity("blood_pressure_systolic", "收缩压", .bloodPressureSystolic, .millimeterOfMercury(), "mmHg"),
        quantity("blood_pressure_diastolic", "舒张压", .bloodPressureDiastolic, .millimeterOfMercury(), "mmHg"),
        quantity("walking_heart_rate", "步行平均心率", .walkingHeartRateAverage, HKUnit.count().unitDivided(by: .minute()), "count/min"),
        quantity("heart_rate_recovery", "一分钟心率恢复", .heartRateRecoveryOneMinute, HKUnit.count().unitDivided(by: .minute()), "count/min"),
        quantity("atrial_fibrillation_burden", "房颤负荷", .atrialFibrillationBurden, .percent(), "%", scale: 100),
        quantity("walking_speed", "步行速度", .walkingSpeed, HKUnit.meter().unitDivided(by: .second()), "m/s"),
        quantity("walking_step_length", "步行步长", .walkingStepLength, .meter(), "m"),
        quantity("walking_asymmetry", "步行不对称性", .walkingAsymmetryPercentage, .percent(), "%", scale: 100),
        quantity("walking_double_support", "双脚支撑时间占比", .walkingDoubleSupportPercentage, .percent(), "%", scale: 100),
        quantity("walking_steadiness", "步行稳定性", .appleWalkingSteadiness, .percent(), "%", scale: 100),
        quantity("stair_ascent_speed", "上楼速度", .stairAscentSpeed, HKUnit.meter().unitDivided(by: .second()), "m/s"),
        quantity("stair_descent_speed", "下楼速度", .stairDescentSpeed, HKUnit.meter().unitDivided(by: .second()), "m/s"),
        quantity("six_minute_walk_distance", "六分钟步行距离", .sixMinuteWalkTestDistance, .meter(), "m"),
        quantity("running_speed", "跑步速度", .runningSpeed, HKUnit.meter().unitDivided(by: .second()), "m/s"),
        quantity("running_power", "跑步功率", .runningPower, .watt(), "W"),
        quantity("running_stride_length", "跑步步幅", .runningStrideLength, .meter(), "m"),
        quantity("running_ground_contact_time", "跑步触地时间", .runningGroundContactTime, .secondUnit(with: .milli), "ms"),
        quantity("running_vertical_oscillation", "跑步垂直振幅", .runningVerticalOscillation, .meterUnit(with: .centi), "cm"),
        quantity("swimming_strokes", "游泳划水次数", .swimmingStrokeCount, .count(), "count"),
        quantity("wheelchair_distance", "轮椅距离", .distanceWheelchair, .meter(), "m"),
        quantity("push_count", "轮椅推动次数", .pushCount, .count(), "count"),
        quantity("blood_glucose", "血糖", .bloodGlucose, HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), "mg/dL"),
        quantity("insulin_delivery", "胰岛素输注", .insulinDelivery, .internationalUnit(), "IU"),
        quantity("basal_body_temperature", "基础体温", .basalBodyTemperature, .degreeCelsius(), "degC"),
        quantity("sleeping_wrist_temperature", "睡眠腕温", .appleSleepingWristTemperature, .degreeCelsius(), "degC"),
        quantity("forced_expiratory_volume", "第一秒用力呼气量", .forcedExpiratoryVolume1, .liter(), "L"),
        quantity("forced_vital_capacity", "用力肺活量", .forcedVitalCapacity, .liter(), "L"),
        quantity("peak_expiratory_flow", "呼气峰值流量", .peakExpiratoryFlowRate, HKUnit.liter().unitDivided(by: .minute()), "L/min"),
        quantity("environmental_audio_exposure", "环境音量", .environmentalAudioExposure, .decibelAWeightedSoundPressureLevel(), "dBASPL"),
        quantity("headphone_audio_exposure", "耳机音量", .headphoneAudioExposure, .decibelAWeightedSoundPressureLevel(), "dBASPL"),
        quantity("uv_exposure", "紫外线指数", .uvExposure, .count(), "count"),
        quantity("underwater_depth", "水下深度", .underwaterDepth, .meter(), "m"),
        quantity("water_temperature", "水温", .waterTemperature, .degreeCelsius(), "degC"),
        quantity("dietary_water", "饮水量", .dietaryWater, .literUnit(with: .milli), "mL"),
        quantity("dietary_energy", "膳食能量", .dietaryEnergyConsumed, .kilocalorie(), "kcal"),
        quantity("dietary_protein", "蛋白质", .dietaryProtein, .gram(), "g"),
        quantity("dietary_carbohydrates", "碳水化合物", .dietaryCarbohydrates, .gram(), "g"),
        quantity("dietary_fat_total", "总脂肪", .dietaryFatTotal, .gram(), "g"),
        quantity("dietary_fat_saturated", "饱和脂肪", .dietaryFatSaturated, .gram(), "g"),
        quantity("dietary_fat_monounsaturated", "单不饱和脂肪", .dietaryFatMonounsaturated, .gram(), "g"),
        quantity("dietary_fat_polyunsaturated", "多不饱和脂肪", .dietaryFatPolyunsaturated, .gram(), "g"),
        quantity("dietary_sugar", "糖", .dietarySugar, .gram(), "g"),
        quantity("dietary_fiber", "膳食纤维", .dietaryFiber, .gram(), "g"),
        quantity("dietary_cholesterol", "胆固醇", .dietaryCholesterol, .gramUnit(with: .milli), "mg"),
        quantity("dietary_sodium", "钠", .dietarySodium, .gramUnit(with: .milli), "mg"),
        quantity("dietary_potassium", "钾", .dietaryPotassium, .gramUnit(with: .milli), "mg"),
        quantity("dietary_calcium", "钙", .dietaryCalcium, .gramUnit(with: .milli), "mg"),
        quantity("dietary_iron", "铁", .dietaryIron, .gramUnit(with: .milli), "mg"),
        quantity("dietary_magnesium", "镁", .dietaryMagnesium, .gramUnit(with: .milli), "mg"),
        quantity("dietary_zinc", "锌", .dietaryZinc, .gramUnit(with: .milli), "mg"),
        quantity("dietary_caffeine", "咖啡因", .dietaryCaffeine, .gramUnit(with: .milli), "mg"),
        quantity("dietary_vitamin_a", "维生素 A", .dietaryVitaminA, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_vitamin_b6", "维生素 B6", .dietaryVitaminB6, .gramUnit(with: .milli), "mg"),
        quantity("dietary_vitamin_b12", "维生素 B12", .dietaryVitaminB12, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_vitamin_c", "维生素 C", .dietaryVitaminC, .gramUnit(with: .milli), "mg"),
        quantity("dietary_vitamin_d", "维生素 D", .dietaryVitaminD, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_vitamin_e", "维生素 E", .dietaryVitaminE, .gramUnit(with: .milli), "mg"),
        quantity("dietary_vitamin_k", "维生素 K", .dietaryVitaminK, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_thiamin", "维生素 B1", .dietaryThiamin, .gramUnit(with: .milli), "mg"),
        quantity("dietary_riboflavin", "维生素 B2", .dietaryRiboflavin, .gramUnit(with: .milli), "mg"),
        quantity("dietary_niacin", "烟酸", .dietaryNiacin, .gramUnit(with: .milli), "mg"),
        quantity("dietary_folate", "叶酸", .dietaryFolate, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_biotin", "生物素", .dietaryBiotin, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_pantothenic_acid", "泛酸", .dietaryPantothenicAcid, .gramUnit(with: .milli), "mg"),
        quantity("dietary_phosphorus", "磷", .dietaryPhosphorus, .gramUnit(with: .milli), "mg"),
        quantity("dietary_iodine", "碘", .dietaryIodine, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_selenium", "硒", .dietarySelenium, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_copper", "铜", .dietaryCopper, .gramUnit(with: .milli), "mg"),
        quantity("dietary_manganese", "锰", .dietaryManganese, .gramUnit(with: .milli), "mg"),
        quantity("dietary_chromium", "铬", .dietaryChromium, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_molybdenum", "钼", .dietaryMolybdenum, .gramUnit(with: .micro), "mcg"),
        quantity("dietary_chloride", "氯", .dietaryChloride, .gramUnit(with: .milli), "mg"),
        Category(id: "mindful_sessions", title: "正念", type: HKCategoryType(.mindfulSession), unit: nil, unitName: nil),
        Category(id: "stand_hours", title: "站立小时", type: HKCategoryType(.appleStandHour), unit: nil, unitName: nil),
        Category(id: "menstrual_flow", title: "月经", type: HKCategoryType(.menstrualFlow), unit: nil, unitName: nil),
        Category(id: "intermenstrual_bleeding", title: "非经期出血", type: HKCategoryType(.intermenstrualBleeding), unit: nil, unitName: nil),
        Category(id: "ovulation_test", title: "排卵检测", type: HKCategoryType(.ovulationTestResult), unit: nil, unitName: nil),
        Category(id: "cervical_mucus", title: "宫颈黏液", type: HKCategoryType(.cervicalMucusQuality), unit: nil, unitName: nil),
        Category(id: "sexual_activity", title: "性活动", type: HKCategoryType(.sexualActivity), unit: nil, unitName: nil),
        Category(id: "high_heart_rate_events", title: "高心率通知", type: HKCategoryType(.highHeartRateEvent), unit: nil, unitName: nil),
        Category(id: "low_heart_rate_events", title: "低心率通知", type: HKCategoryType(.lowHeartRateEvent), unit: nil, unitName: nil),
        Category(id: "irregular_heart_rhythm_events", title: "心律不齐通知", type: HKCategoryType(.irregularHeartRhythmEvent), unit: nil, unitName: nil)
    ]
    // Match HealthKit's aggregation style, including nutrition and mobility totals.
    static let dailyTotals = Set(categories.filter { ($0.type as? HKQuantityType)?.aggregationStyle == .cumulative }.map(\.id))
    nonisolated static let disclosure = "iOS does not disclose read authorization. Empty results may mean no data or access not granted; never interpret them as zero. Sleep samples may overlap across sources."
    private let store = HKHealthStore()
    private var queries: [UUID: (HKQuery, CheckedContinuation<[String: Any], Error>, Task<Void, Never>)] = [:]
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func authorize(_ categories: Set<String>) async throws {
        let types = Set(Self.categories.filter { categories.contains($0.id) }.map { $0.type as HKObjectType })
        guard available, !types.isEmpty, types.count == categories.count else { throw PortalError.server("此设备不支持所选健康数据。") }
        try await store.requestAuthorization(toShare: [], read: types)
    }

    static func range(_ args: [String: Any], now: Date = Date()) throws -> (Date, Date) {
        let end = args["end"] == nil ? now : try LocalPortalRules.date(args, "end")
        let start = args["start"] == nil ? end.addingTimeInterval(-7 * 86400) : try LocalPortalRules.date(args, "start")
        guard end > start, end.timeIntervalSince(start) <= 31 * 86400 else { throw PortalError.server("健康查询时间范围需在 31 天内。") }
        return (start, end)
    }
    func read(_ args: [String: Any]) async throws -> [String: Any] {
        let category = try LocalPortalRules.string(args, "category")
        guard available, let item = Self.categories.first(where: { $0.id == category }) else { throw PortalError.server("健康类别不可用。") }
        let (start, end) = try Self.range(args)
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
                let query: HKQuery
                if Self.dailyTotals.contains(category), let type = item.type as? HKQuantityType, let unit = item.unit {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    let anchor = calendar.startOfDay(for: start)
                    let statistics = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(calendar: calendar, timeZone: calendar.timeZone, day: 1))
                    statistics.initialResultsHandler = { [weak self] _, collection, error in
                        var rows = [[String: Any]]()
                        collection?.enumerateStatistics(from: start, to: end.addingTimeInterval(-0.001)) { statistics, _ in
                            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                                rows.append(["start": max(statistics.startDate, start).ISO8601Format(), "end": min(statistics.endDate, end).ISO8601Format(), "value": value * item.scale, "unit": item.unitName ?? ""])
                            }
                        }
                        let result: [String: Any] = ["category": category, "records": rows, "aggregation": "daily_sum_utc", "truncated": false, "read_authorization": "not_disclosed", "note": IOSPortalHealth.disclosure]
                        Task { @MainActor in self?.finish(id, error.map { .failure($0) } ?? .success(result)) }
                    }
                    query = statistics
                } else {
                    query = HKSampleQuery(sampleType: item.type, predicate: predicate, limit: 201, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { [weak self] _, samples, error in
                        let samples = samples ?? []
                        Task { @MainActor in
                            let rows = samples.prefix(200).map { Self.encode($0, category: item) }
                            self?.finish(id, error.map { .failure($0) } ?? .success(["category": category, "records": rows, "truncated": samples.count > 200, "read_authorization": "not_disclosed", "note": Self.disclosure]))
                        }
                    }
                }
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    self?.finish(id, .failure(PortalError.server("健康查询超时，请缩小时间范围后重试。")))
                }
                queries[id] = (query, continuation, timeout)
                store.execute(query)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) } }
    }
    private func finish(_ id: UUID, _ result: Result<[String: Any], Error>) {
        guard let (query, continuation, timeout) = queries.removeValue(forKey: id) else { return }
        store.stop(query); timeout.cancel()
        continuation.resume(with: result.mapError { error in
            guard let healthError = error as? HKError else { return error }
            let hint: String
            switch healthError.code {
            case .errorAuthorizationDenied, .errorRequiredAuthorizationDenied: hint = "系统拒绝此健康操作，请在健康 App → 个人头像 → App → Being 检查共享范围。"
            case .errorAuthorizationNotDetermined: hint = "尚未完成系统健康选择，请在 Portal 中关联 Apple 健康。"
            case .errorDatabaseInaccessible: hint = "健康数据库当前不可访问，请解锁 iPhone 并保持 Being 在前台后重试。"
            case .errorHealthDataUnavailable: hint = "此设备的健康数据不可用。"
            case .errorHealthDataRestricted: hint = "健康数据受系统限制，请检查设备设置。"
            case .errorInvalidArgument: hint = "HealthKit 拒绝了查询参数，请检查 category 和 start/end 时间范围。"
            case .errorNoData: hint = "此查询没有可返回的健康记录，不代表数值为零。"
            default: hint = "系统健康查询未完成，请稍后重试。"
            }
            return PortalError.server("HealthKit 错误 \(healthError.code.rawValue)：" + hint)
        })
    }
    static func encode(_ sample: HKSample, category: Category) -> [String: Any] {
        var row: [String: Any] = ["start": sample.startDate.ISO8601Format(), "end": sample.endDate.ISO8601Format(), "source": sample.sourceRevision.source.name]
        if let quantity = sample as? HKQuantitySample, let unit = category.unit {
            row["value"] = quantity.quantity.doubleValue(for: unit) * category.scale; row["unit"] = category.unitName
        }
        if let value = sample as? HKCategorySample {
            row["value"] = value.value
            row["category_type"] = value.categoryType.identifier
            if category.id == "sleep" {
                row["stage"] = [0: "in_bed", 1: "asleep_unspecified", 2: "awake", 3: "asleep_core", 4: "asleep_deep", 5: "asleep_rem"][value.value] ?? "unknown"
            }
            row["duration_seconds"] = sample.endDate.timeIntervalSince(sample.startDate)
        }
        if let workout = sample as? HKWorkout {
            row["activity_type"] = workout.workoutActivityType.rawValue
            row["duration_seconds"] = workout.duration
        }
        return row
    }
}
