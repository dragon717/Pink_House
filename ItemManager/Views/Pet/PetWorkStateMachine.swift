import Foundation

enum PetWorkRuntimeState: Equatable {
    case idle
    case manualWorking(PetJob)
    case autoWorking(PetJob)
    case sleepSuspendedWorking(PetJob, isAutomatic: Bool)
    case interrupted
}

struct PetWorkStartResult: Equatable {
    let didStart: Bool
    let job: PetJob
    let rewardCurrency: PetCurrency
    let startedAutomatically: Bool
    let message: String
}

struct PetWorkStopResult: Equatable {
    let job: PetJob
    let rewardCurrency: PetCurrency
    let earnedAmount: Int
    let wasAutomatic: Bool
    let wasInterrupted: Bool
    let message: String
}

enum PetWorkStateMachine {
    static func runtimeState(
        for status: PetStatus,
        isFixedSleepTime: Bool = false,
        isInterrupted: Bool = false
    ) -> PetWorkRuntimeState {
        if isInterrupted { return .interrupted }
        guard status.currentJob != .none else { return .idle }
        if isFixedSleepTime {
            return .sleepSuspendedWorking(status.currentJob, isAutomatic: status.currentJobStartedAutomatically)
        }
        if status.currentJobStartedAutomatically {
            return .autoWorking(status.currentJob)
        }
        return .manualWorking(status.currentJob)
    }

    static func selectedPet(from status: PetStatus) -> PetCharacter {
        guard let petId = status.selectedPetId,
              let pet = PetCharacter(rawValue: petId) else {
            return .naicha
        }
        return pet
    }

    static func normalizedRewardCurrency(_ currency: PetCurrency) -> PetCurrency {
        currency == .meowCoin ? .fishCoin : currency
    }

    static func resolvedAutoWorkRewardCurrency(for status: PetStatus) -> PetCurrency {
        status.autoWorkRewardMode.resolvedCurrency(for: selectedPet(from: status))
    }

    static func remainingJobIncomeQuota(in status: PetStatus, for currency: PetCurrency) -> Int {
        switch normalizedRewardCurrency(currency) {
        case .fishCoin:
            return max(0, PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned)
        case .boneCoin:
            return max(0, PetStatus.dailyBoneCoinLimit - status.dailyBoneCoinEarned)
        case .meowCoin:
            return 0
        }
    }

    static func startJob(
        _ job: PetJob,
        in status: inout PetStatus,
        isAutomatic: Bool = false,
        rewardCurrency: PetCurrency? = nil,
        now: Date = Date(),
        allowReplacingExistingJob: Bool = false
    ) -> PetWorkStartResult {
        guard job != .none else {
            return PetWorkStartResult(
                didStart: false,
                job: .none,
                rewardCurrency: normalizedRewardCurrency(rewardCurrency ?? .fishCoin),
                startedAutomatically: isAutomatic,
                message: "我现在没有要开始的新工作。"
            )
        }

        if status.currentJob != .none && !allowReplacingExistingJob {
            return PetWorkStartResult(
                didStart: false,
                job: status.currentJob,
                rewardCurrency: status.currentJobRewardCurrency,
                startedAutomatically: status.currentJobStartedAutomatically,
                message: "\(status.displayName)已经在\(status.currentJob.rawValue)啦，先下班再换工作吧。"
            )
        }

        let resolvedCurrency = normalizedRewardCurrency(
            rewardCurrency ?? (isAutomatic ? resolvedAutoWorkRewardCurrency(for: status) : .fishCoin)
        )
        status.currentJob = job
        status.jobStartTime = now
        status.currentJobStartedAutomatically = isAutomatic
        status.currentJobRewardCurrency = resolvedCurrency
        status.currentJobEarnedAmount = 0
        status.currentJobEarnedFishCoin = 0

        let prefix = isAutomatic ? "自动打工" : "开始打工"
        return PetWorkStartResult(
            didStart: true,
            job: job,
            rewardCurrency: resolvedCurrency,
            startedAutomatically: isAutomatic,
            message: "\(prefix): \(job.rawValue)，这次赚\(resolvedCurrency.rawValue)。"
        )
    }

    static func stopJob(in status: inout PetStatus, isInterrupted: Bool = false) -> PetWorkStopResult? {
        guard status.currentJob != .none else { return nil }

        let job = status.currentJob
        let rewardCurrency = normalizedRewardCurrency(status.currentJobRewardCurrency)
        let earnedAmount = status.currentJobEarnedAmount
        let wasAutomatic = status.currentJobStartedAutomatically

        status.currentJob = .none
        status.jobStartTime = nil
        status.currentJobStartedAutomatically = false

        let message: String
        if isInterrupted {
            message = "\(status.displayName)状态太低，被迫停止打工。"
        } else {
            message = "\(status.displayName)下班啦，本次赚了 \(earnedAmount) \(rewardCurrency.rawValue)。"
        }

        return PetWorkStopResult(
            job: job,
            rewardCurrency: rewardCurrency,
            earnedAmount: earnedAmount,
            wasAutomatic: wasAutomatic,
            wasInterrupted: isInterrupted,
            message: message
        )
    }

    static func updateAutoWorkEnabled(_ isEnabled: Bool, in status: inout PetStatus) -> PetWorkStopResult? {
        status.isAutoWorkEnabled = isEnabled
        if !isEnabled, status.currentJobStartedAutomatically, status.currentJob != .none {
            return stopJob(in: &status)
        }
        return nil
    }

    static func updateAutoWorkStrategy(_ strategy: PetAutoWorkStrategy, in status: inout PetStatus) {
        status.autoWorkStrategy = strategy
    }

    static func updateAutoWorkRewardMode(_ rewardMode: PetAutoWorkRewardMode, in status: inout PetStatus) {
        status.autoWorkRewardMode = rewardMode
        if status.currentJobStartedAutomatically {
            status.currentJobRewardCurrency = resolvedAutoWorkRewardCurrency(for: status)
        }
    }

    static func autoWorkStatusSummary(for status: PetStatus) -> String {
        guard status.isAutoWorkEnabled else { return "自动打工未开启" }
        if status.currentJobStartedAutomatically, status.currentJob != .none {
            return "\(status.currentJob.rawValue)进行中，已赚 \(status.currentJobEarnedAmount) \(status.currentJobRewardCurrency.rawValue)"
        }
        let currency = resolvedAutoWorkRewardCurrency(for: status)
        if remainingJobIncomeQuota(in: status, for: currency) <= 0 {
            return "今日\(currency.rawValue)收益已达上限"
        }
        if let blocker = status.autoWorkStrategy.startThresholds.blockerDescription(for: status) {
            return blocker
        }
        return "状态不错，闲下来会自动去打工"
    }

    @discardableResult
    static func addJobIncome(_ amount: Int, currency: PetCurrency, to status: inout PetStatus) -> Int {
        let actualCurrency = normalizedRewardCurrency(currency)
        let actualEarned = min(max(0, amount), remainingJobIncomeQuota(in: status, for: actualCurrency))
        guard actualEarned > 0 else { return 0 }

        switch actualCurrency {
        case .fishCoin:
            let (newValue, overflow) = status.fishCoin.addingReportingOverflow(actualEarned)
            guard !overflow else { return 0 }
            status.fishCoin = newValue
            status.dailyFishCoinEarned += actualEarned
            status.currentJobEarnedFishCoin += actualEarned
        case .boneCoin:
            let (newValue, overflow) = status.boneCoin.addingReportingOverflow(actualEarned)
            guard !overflow else { return 0 }
            status.boneCoin = newValue
            status.dailyBoneCoinEarned += actualEarned
        case .meowCoin:
            return 0
        }

        status.currentJobEarnedAmount += actualEarned
        return actualEarned
    }

    static func shouldStartAutoWork(
        status: PetStatus,
        currentStateIsIdle: Bool,
        currentMinute: Int,
        forceSleepMinuteStart: Int
    ) -> Bool {
        guard status.isAutoWorkEnabled else { return false }
        guard status.currentJob == .none else { return false }
        guard currentStateIsIdle else { return false }
        guard currentMinute < forceSleepMinuteStart else { return false }
        guard status.autoWorkStrategy.startThresholds.isSatisfied(by: status) else { return false }
        return remainingJobIncomeQuota(in: status, for: resolvedAutoWorkRewardCurrency(for: status)) > 0
    }

    static func startAutoWorkIfNeeded(
        in status: inout PetStatus,
        currentStateIsIdle: Bool,
        currentMinute: Int,
        forceSleepMinuteStart: Int,
        now: Date
    ) -> PetWorkStartResult? {
        guard shouldStartAutoWork(
            status: status,
            currentStateIsIdle: currentStateIsIdle,
            currentMinute: currentMinute,
            forceSleepMinuteStart: forceSleepMinuteStart
        ) else {
            return nil
        }

        let job = status.autoWorkStrategy.preferredJob(for: status)
        let rewardCurrency = resolvedAutoWorkRewardCurrency(for: status)
        return startJob(job, in: &status, isAutomatic: true, rewardCurrency: rewardCurrency, now: now)
    }

    static func shouldStopAutoWorkForProtection(status: PetStatus) -> Bool {
        guard status.currentJobStartedAutomatically else { return false }
        if remainingJobIncomeQuota(in: status, for: status.currentJobRewardCurrency) <= 0 {
            return true
        }
        return !status.autoWorkStrategy.stopThresholds.isSatisfied(by: status)
    }

    static func jobToken(for job: PetJob) -> String {
        switch job {
        case .none: return "none"
        case .waiter: return "waiter"
        case .security: return "security"
        case .streamer: return "streamer"
        }
    }

    static func job(forToken token: String) -> PetJob? {
        switch token {
        case "waiter": return .waiter
        case "security": return .security
        case "streamer": return .streamer
        default: return nil
        }
    }

    static func currencyToken(for currency: PetCurrency) -> String {
        switch normalizedRewardCurrency(currency) {
        case .fishCoin: return "fishCoin"
        case .boneCoin: return "boneCoin"
        case .meowCoin: return "fishCoin"
        }
    }

    static func currency(forToken token: String) -> PetCurrency? {
        switch token {
        case "fishCoin": return .fishCoin
        case "boneCoin": return .boneCoin
        default: return nil
        }
    }

    static func rewardMode(forToken token: String) -> PetAutoWorkRewardMode? {
        switch token {
        case "followPet": return .followPet
        case "fishCoin": return .fishCoin
        case "boneCoin": return .boneCoin
        default: return nil
        }
    }
}
