// Analytics.mo - Advanced Analytics and Reporting Canister

import Types "./Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Float "mo:base/Float";

actor Analytics {
    
    // ============= TYPES =============
    
    type TimeSeriesData = {
        timestamp: Time.Time;
        value: Nat;
    };
    
    type CategoryDistribution = {
        category: Types.GoalCategory;
        count: Nat;
        totalValue: Nat;
        percentage: Float;
    };
    
    type TierDistribution = {
        tier: Types.UserTier;
        count: Nat;
        averageSaved: Nat;
    };
    
    type DailyMetrics = {
        date: Time.Time;
        newGoals: Nat;
        completedGoals: Nat;
        totalDeposits: Nat;
        totalWithdrawals: Nat;
        activeUsers: Nat;
        tvl: Nat;
    };
    
    type MonthlyReport = {
        month: Nat;
        year: Nat;
        totalGoalsCreated: Nat;
        totalDeposits: Nat;
        totalWithdrawals: Nat;
        totalInterestPaid: Nat;
        newUsers: Nat;
        activeUsers: Nat;
        averageGoalSize: Nat;
        completionRate: Float;
    };
    
    // ============= STATE =============
    
    private stable var savingsCanisterPrincipal : Principal = Principal.fromText("aaaaa-aa");
    private stable var userMgmtCanisterPrincipal : Principal = Principal.fromText("aaaaa-aa");
    
    private var dailyMetrics = HashMap.HashMap<Nat, DailyMetrics>(365, Nat.equal, Nat.hash);
    private var categoryStats = HashMap.HashMap<Text, Nat>(20, Text.equal, Text.hash);
    
    private stable var dailyMetricsEntries : [(Nat, DailyMetrics)] = [];
    private stable var categoryStatsEntries : [(Text, Nat)] = [];
    
    system func preupgrade() {
        dailyMetricsEntries := Iter.toArray(dailyMetrics.entries());
        categoryStatsEntries := Iter.toArray(categoryStats.entries());
    };
    
    system func postupgrade() {
        dailyMetrics := HashMap.fromIter<Nat, DailyMetrics>(dailyMetricsEntries.vals(), 365, Nat.equal, Nat.hash);
        categoryStats := HashMap.fromIter<Text, Nat>(categoryStatsEntries.vals(), 20, Text.equal, Text.hash);
        
        dailyMetricsEntries := [];
        categoryStatsEntries := [];
    };
    
    // ============= SETUP =============
    
    public shared(msg) func setSavingsCanister(canister: Principal) : async () {
        savingsCanisterPrincipal := canister;
    };
    
    public shared(msg) func setUserMgmtCanister(canister: Principal) : async () {
        userMgmtCanisterPrincipal := canister;
    };
    
    // ============= DATA COLLECTION =============
    
    public shared(msg) func recordDailyMetrics(metrics: DailyMetrics) : async () {
        let dayKey = getDayKey(metrics.date);
        dailyMetrics.put(dayKey, metrics);
    };
    
    public shared(msg) func incrementCategoryCount(category: Types.GoalCategory) : async () {
        let catName = debug_show(category);
        let current = switch (categoryStats.get(catName)) {
            case null { 0 };
            case (?c) { c };
        };
        categoryStats.put(catName, current + 1);
    };
    
    private func getDayKey(timestamp: Time.Time) : Nat {
        let days = Int.abs(timestamp) / (24 * 60 * 60 * 1_000_000_000);
        Int.abs(days)
    };
    
    // ============= ANALYTICS QUERIES =============
    
    // Get TVL over time (last N days)
    public query func getTVLHistory(days: Nat) : async [TimeSeriesData] {
        let buffer = Buffer.Buffer<TimeSeriesData>(days);
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        for (i in Iter.range(0, days - 1)) {
            let dayTimestamp = now - (i * oneDayNanos);
            let dayKey = getDayKey(dayTimestamp);
            
            switch (dailyMetrics.get(dayKey)) {
                case (?metrics) {
                    buffer.add({
                        timestamp = dayTimestamp;
                        value = metrics.tvl;
                    });
                };
                case null {
                    buffer.add({
                        timestamp = dayTimestamp;
                        value = 0;
                    });
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // Get deposit/withdrawal trends
    public query func getFlowHistory(days: Nat) : async {
        deposits: [TimeSeriesData];
        withdrawals: [TimeSeriesData];
    } {
        let depositsBuffer = Buffer.Buffer<TimeSeriesData>(days);
        let withdrawalsBuffer = Buffer.Buffer<TimeSeriesData>(days);
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        for (i in Iter.range(0, days - 1)) {
            let dayTimestamp = now - (i * oneDayNanos);
            let dayKey = getDayKey(dayTimestamp);
            
            switch (dailyMetrics.get(dayKey)) {
                case (?metrics) {
                    depositsBuffer.add({
                        timestamp = dayTimestamp;
                        value = metrics.totalDeposits;
                    });
                    withdrawalsBuffer.add({
                        timestamp = dayTimestamp;
                        value = metrics.totalWithdrawals;
                    });
                };
                case null {
                    depositsBuffer.add({ timestamp = dayTimestamp; value = 0 });
                    withdrawalsBuffer.add({ timestamp = dayTimestamp; value = 0 });
                };
            };
        };
        
        {
            deposits = Buffer.toArray(depositsBuffer);
            withdrawals = Buffer.toArray(withdrawalsBuffer);
        }
    };
    
    // Get category distribution
    public query func getCategoryDistribution() : async [CategoryDistribution] {
        let buffer = Buffer.Buffer<CategoryDistribution>(10);
        var totalCount = 0;
        
        // Calculate total
        for ((_, count) in categoryStats.entries()) {
            totalCount += count;
        };
        
        // Create distribution
        for ((cat, count) in categoryStats.entries()) {
            let percentage = if (totalCount > 0) {
                Float.fromInt(count) / Float.fromInt(totalCount) * 100.0
            } else { 0.0 };
            
            // Parse category (this is simplified)
            let category : Types.GoalCategory = #Vacation; // TODO: Proper parsing
            
            buffer.add({
                category = category;
                count = count;
                totalValue = 0; // TODO: Track value
                percentage = percentage;
            });
        };
        
        Buffer.toArray(buffer)
    };
    
    // Get active users over time
    public query func getActiveUsersHistory(days: Nat) : async [TimeSeriesData] {
        let buffer = Buffer.Buffer<TimeSeriesData>(days);
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        for (i in Iter.range(0, days - 1)) {
            let dayTimestamp = now - (i * oneDayNanos);
            let dayKey = getDayKey(dayTimestamp);
            
            switch (dailyMetrics.get(dayKey)) {
                case (?metrics) {
                    buffer.add({
                        timestamp = dayTimestamp;
                        value = metrics.activeUsers;
                    });
                };
                case null {
                    buffer.add({ timestamp = dayTimestamp; value = 0 });
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // Get new goals over time
    public query func getNewGoalsHistory(days: Nat) : async [TimeSeriesData] {
        let buffer = Buffer.Buffer<TimeSeriesData>(days);
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        for (i in Iter.range(0, days - 1)) {
            let dayTimestamp = now - (i * oneDayNanos);
            let dayKey = getDayKey(dayTimestamp);
            
            switch (dailyMetrics.get(dayKey)) {
                case (?metrics) {
                    buffer.add({
                        timestamp = dayTimestamp;
                        value = metrics.newGoals;
                    });
                };
                case null {
                    buffer.add({ timestamp = dayTimestamp; value = 0 });
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // Calculate growth rate
    public query func calculateGrowthRate(days: Nat) : async {
        tvlGrowth: Float;
        userGrowth: Float;
        goalGrowth: Float;
    } {
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        let todayKey = getDayKey(now);
        let pastKey = getDayKey(now - (days * oneDayNanos));
        
        let todayMetrics = dailyMetrics.get(todayKey);
        let pastMetrics = dailyMetrics.get(pastKey);
        
        let tvlGrowth = switch (todayMetrics, pastMetrics) {
            case (?today, ?past) {
                if (past.tvl > 0) {
                    Float.fromInt(Int.abs(today.tvl - past.tvl)) / Float.fromInt(past.tvl) * 100.0
                } else { 0.0 }
            };
            case _ { 0.0 };
        };
        
        let userGrowth = switch (todayMetrics, pastMetrics) {
            case (?today, ?past) {
                if (past.activeUsers > 0) {
                    Float.fromInt(Int.abs(today.activeUsers - past.activeUsers)) / Float.fromInt(past.activeUsers) * 100.0
                } else { 0.0 }
            };
            case _ { 0.0 };
        };
        
        let goalGrowth = switch (todayMetrics, pastMetrics) {
            case (?today, ?past) {
                let todayTotal = today.newGoals;
                let pastTotal = past.newGoals;
                if (pastTotal > 0) {
                    Float.fromInt(Int.abs(todayTotal - pastTotal)) / Float.fromInt(pastTotal) * 100.0
                } else { 0.0 }
            };
            case _ { 0.0 };
        };
        
        {
            tvlGrowth = tvlGrowth;
            userGrowth = userGrowth;
            goalGrowth = goalGrowth;
        }
    };
    
    // Get retention metrics
    public query func getRetentionMetrics() : async {
        dailyActiveUsers: Nat;
        weeklyActiveUsers: Nat;
        monthlyActiveUsers: Nat;
        dau_mau_ratio: Float;
    } {
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        let todayKey = getDayKey(now);
        let weekKey = getDayKey(now - (7 * oneDayNanos));
        let monthKey = getDayKey(now - (30 * oneDayNanos));
        
        var dau = 0;
        var wau = 0;
        var mau = 0;
        
        // Simplified calculation - in production, track unique users
        switch (dailyMetrics.get(todayKey)) {
            case (?metrics) { dau := metrics.activeUsers };
            case null {};
        };
        
        // Sum weekly
        for (i in Iter.range(0, 6)) {
            let key = getDayKey(now - (i * oneDayNanos));
            switch (dailyMetrics.get(key)) {
                case (?metrics) { wau += metrics.activeUsers };
                case null {};
            };
        };
        wau := wau / 7; // Average
        
        // Sum monthly
        for (i in Iter.range(0, 29)) {
            let key = getDayKey(now - (i * oneDayNanos));
            switch (dailyMetrics.get(key)) {
                case (?metrics) { mau += metrics.activeUsers };
                case null {};
            };
        };
        mau := mau / 30; // Average
        
        let ratio = if (mau > 0) {
            Float.fromInt(dau) / Float.fromInt(mau)
        } else { 0.0 };
        
        {
            dailyActiveUsers = dau;
            weeklyActiveUsers = wau;
            monthlyActiveUsers = mau;
            dau_mau_ratio = ratio;
        }
    };
    
    // Get top performing goals
    public func getTopGoals(limit: Nat) : async [{
        goalId: Nat;
        title: Text;
        currentAmount: Nat;
        targetAmount: Nat;
        progress: Float;
    }] {
        // This would call the savings canister to get goal data
        // Placeholder implementation
        []
    };
    
    // Generate monthly report
    public func generateMonthlyReport(month: Nat, year: Nat) : async ?MonthlyReport {
        // Calculate metrics for the entire month
        let firstDay = Time.now(); // TODO: Calculate first day of month
        let lastDay = Time.now();  // TODO: Calculate last day of month
        
        var totalGoalsCreated = 0;
        var totalDeposits = 0;
        var totalWithdrawals = 0;
        var completedGoals = 0;
        var totalGoals = 0;
        
        // Iterate through daily metrics for the month
        for ((key, metrics) in dailyMetrics.entries()) {
            totalGoalsCreated += metrics.newGoals;
            totalDeposits += metrics.totalDeposits;
            totalWithdrawals += metrics.totalWithdrawals;
            completedGoals += metrics.completedGoals;
        };
        
        let completionRate = if (totalGoals > 0) {
            Float.fromInt(completedGoals) / Float.fromInt(totalGoals) * 100.0
        } else { 0.0 };
        
        ?{
            month = month;
            year = year;
            totalGoalsCreated = totalGoalsCreated;
            totalDeposits = totalDeposits;
            totalWithdrawals = totalWithdrawals;
            totalInterestPaid = 0; // TODO: Track this
            newUsers = 0; // TODO: Track this
            activeUsers = 0; // TODO: Track this
            averageGoalSize = if (totalGoalsCreated > 0) {
                totalDeposits / totalGoalsCreated
            } else { 0 };
            completionRate = completionRate;
        }
    };
    
    // Get comparison metrics
    public query func getComparativeMetrics() : async {
        vsLastWeek: {
            tvl: Float;
            users: Float;
            goals: Float;
        };
        vsLastMonth: {
            tvl: Float;
            users: Float;
            goals: Float;
        };
    } {
        let now = Time.now();
        let oneDayNanos = 24 * 60 * 60 * 1_000_000_000;
        
        let todayKey = getDayKey(now);
        let weekAgoKey = getDayKey(now - (7 * oneDayNanos));
        let monthAgoKey = getDayKey(now - (30 * oneDayNanos));
        
        let today = dailyMetrics.get(todayKey);
        let weekAgo = dailyMetrics.get(weekAgoKey);
        let monthAgo = dailyMetrics.get(monthAgoKey);
        
        let vsWeekTvl = calculatePercentChange(today, weekAgo, func(m: DailyMetrics) : Nat { m.tvl });
        let vsWeekUsers = calculatePercentChange(today, weekAgo, func(m: DailyMetrics) : Nat { m.activeUsers });
        let vsWeekGoals = calculatePercentChange(today, weekAgo, func(m: DailyMetrics) : Nat { m.newGoals });
        
        let vsMonthTvl = calculatePercentChange(today, monthAgo, func(m: DailyMetrics) : Nat { m.tvl });
        let vsMonthUsers = calculatePercentChange(today, monthAgo, func(m: DailyMetrics) : Nat { m.activeUsers });
        let vsMonthGoals = calculatePercentChange(today, monthAgo, func(m: DailyMetrics) : Nat { m.newGoals });
        
        {
            vsLastWeek = {
                tvl = vsWeekTvl;
                users = vsWeekUsers;
                goals = vsWeekGoals;
            };
            vsLastMonth = {
                tvl = vsMonthTvl;
                users = vsMonthUsers;
                goals = vsMonthGoals;
            };
        }
    };
    
    private func calculatePercentChange(
        current: ?DailyMetrics,
        past: ?DailyMetrics,
        getValue: (DailyMetrics) -> Nat
    ) : Float {
        switch (current, past) {
            case (?c, ?p) {
                let currentVal = getValue(c);
                let pastVal = getValue(p);
                if (pastVal > 0) {
                    Float.fromInt(Int.abs(currentVal - pastVal)) / Float.fromInt(pastVal) * 100.0
                } else if (currentVal > 0) {
                    100.0
                } else {
                    0.0
                }
            };
            case _ { 0.0 };
        }
    };
}