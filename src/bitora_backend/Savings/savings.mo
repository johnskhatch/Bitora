// Main.mo - Enhanced Bitcoin Savings Lock Main Canister

import Types "./Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Option "mo:base/Option";
import Text "mo:base/Text";
import Order "mo:base/Order";

actor class SavingsLock(userManagementCanister: Principal) = this {
    
    // ============= STATE VARIABLES =============
    
    private stable var nextGoalId : Nat = 0;
    private stable var nextTransactionId : Nat = 0;
    private stable var ckBtcLedgerPrincipal : Principal = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
    
    private var goals = HashMap.HashMap<Nat, Types.SavingsGoal>(100, Nat.equal, Nat.hash);
    private var userGoals = HashMap.HashMap<Principal, [Nat]>(100, Principal.equal, Principal.hash);
    private var transactions = HashMap.HashMap<Nat, Types.Transaction>(1000, Nat.equal, Nat.hash);
    private var userTransactions = HashMap.HashMap<Principal, [Nat]>(100, Principal.equal, Principal.hash);
    private var goalComments = HashMap.HashMap<Nat, [Types.GoalComment]>(100, Nat.equal, Nat.hash);
    
    private stable var totalInterestPool : Nat = 0;
    private stable var totalValueLocked : Nat = 0;
    private stable var totalPenaltiesCollected : Nat = 0;
    private stable var totalInterestPaid : Nat = 0;
    
    // Constants
    private let NANOSECONDS_PER_DAY : Int = 24 * 60 * 60 * 1_000_000_000;
    private let NANOSECONDS_PER_YEAR : Int = 365 * NANOSECONDS_PER_DAY;
    private let BASIS_POINTS : Nat = 10_000;
    private let DEFAULT_INTEREST_RATE : Nat = 500; // 5% APY
    
    // Stable storage
    private stable var goalsEntries : [(Nat, Types.SavingsGoal)] = [];
    private stable var userGoalsEntries : [(Principal, [Nat])] = [];
    private stable var transactionsEntries : [(Nat, Types.Transaction)] = [];
    private stable var userTransactionsEntries : [(Principal, [Nat])] = [];
    private stable var goalCommentsEntries : [(Nat, [Types.GoalComment])] = [];
    
    // User management canister actor
    let userMgmt = actor(Principal.toText(userManagementCanister)) : actor {
        updateUserStats : (Principal, Nat, Nat, Nat) -> async ();
        updateUserTier : (Principal, Nat) -> async ();
        createNotification : (Principal, Types.NotificationType, Text, ?Text) -> async Nat;
    };
    
    system func preupgrade() {
        goalsEntries := Iter.toArray(goals.entries());
        userGoalsEntries := Iter.toArray(userGoals.entries());
        transactionsEntries := Iter.toArray(transactions.entries());
        userTransactionsEntries := Iter.toArray(userTransactions.entries());
        goalCommentsEntries := Iter.toArray(goalComments.entries());
    };
    
    system func postupgrade() {
        goals := HashMap.fromIter<Nat, Types.SavingsGoal>(goalsEntries.vals(), 100, Nat.equal, Nat.hash);
        userGoals := HashMap.fromIter<Principal, [Nat]>(userGoalsEntries.vals(), 100, Principal.equal, Principal.hash);
        transactions := HashMap.fromIter<Nat, Types.Transaction>(transactionsEntries.vals(), 1000, Nat.equal, Nat.hash);
        userTransactions := HashMap.fromIter<Principal, [Nat]>(userTransactionsEntries.vals(), 100, Principal.equal, Principal.hash);
        goalComments := HashMap.fromIter<Nat, [Types.GoalComment]>(goalCommentsEntries.vals(), 100, Nat.equal, Nat.hash);
        
        goalsEntries := [];
        userGoalsEntries := [];
        transactionsEntries := [];
        userTransactionsEntries := [];
        goalCommentsEntries := [];
    };
    
    // ============= HELPER FUNCTIONS =============
    
    private func createTransaction(
        goalId: Nat,
        user: Principal,
        txType: Types.TransactionType,
        amount: Nat,
        fee: Nat,
        blockIndex: ?Nat,
        memo: ?Text
    ) : Nat {
        let txId = nextTransactionId;
        nextTransactionId += 1;
        
        let transaction : Types.Transaction = {
            id = txId;
            goalId = goalId;
            user = user;
            txType = txType;
            amount = amount;
            fee = fee;
            timestamp = Time.now();
            blockIndex = blockIndex;
            status = #Completed;
            memo = memo;
        };
        
        transactions.put(txId, transaction);
        
        let existing = switch (userTransactions.get(user)) {
            case null { [] };
            case (?t) { t };
        };
        userTransactions.put(user, Array.append(existing, [txId]));
        
        txId
    };
    
    private func calculateInterest(goal: Types.SavingsGoal) : Nat {
        let now = Time.now();
        let timeElapsed = now - goal.createdAt;
        
        if (timeElapsed <= 0) { return 0 };
        
        let principal = goal.currentAmount;
        let rate = goal.interestRate;
        let timeInYears = Int.abs(timeElapsed) / Int.abs(NANOSECONDS_PER_YEAR);
        
        (principal * rate * timeInYears) / BASIS_POINTS
    };
    
    private func updateGlobalStats(amount: Int, isDeposit: Bool) {
        if (isDeposit) {
            totalValueLocked := Int.abs(Int.abs(totalValueLocked) + amount);
        } else {
            let current = Int.abs(totalValueLocked);
            let change = Int.abs(amount);
            totalValueLocked := if (current >= change) { current - change } else { 0 };
        };
    };
    
    private func checkMilestones(goal: Types.SavingsGoal) : Types.SavingsGoal {
        let progressPercent = (goal.currentAmount * 100) / goal.targetAmount;
        
        let updatedMilestones = Array.map<Types.Milestone, Types.Milestone>(goal.milestones, func(m) {
            if (not m.reached and progressPercent >= m.percentage) {
                // Milestone reached!
                ignore userMgmt.createNotification(
                    goal.owner,
                    #GoalMilestone,
                    "🎯 Milestone reached: " # Nat.toText(m.percentage) # "% of your goal '" # goal.title # "'",
                    null
                );
                { m with reached = true; reachedAt = ?Time.now() }
            } else { m }
        });
        
        { goal with milestones = updatedMilestones; updatedAt = Time.now() }
    };
    
    // ============= GOAL MANAGEMENT =============
    
    public shared(msg) func createGoal(request: Types.CreateGoalRequest) : async Types.CreateGoalResult {
        let caller = msg.caller;
        
        // Validation
        if (request.targetAmount == 0) {
            return #err("Target amount must be greater than 0");
        };
        
        if (request.lockDurationDays == 0) {
            return #err("Lock duration must be at least 1 day");
        };
        
        if (request.lockDurationDays > 3650) {
            return #err("Lock duration cannot exceed 10 years");
        };
        
        if (request.emergencyWithdrawalPenalty > 5000) {
            return #err("Emergency withdrawal penalty cannot exceed 50%");
        };
        
        if (Text.size(request.title) == 0 or Text.size(request.title) > 100) {
            return #err("Title must be between 1 and 100 characters");
        };
        
        let goalId = nextGoalId;
        nextGoalId += 1;
        
        let now = Time.now();
        let unlockTime = now + (Int.abs(request.lockDurationDays) * NANOSECONDS_PER_DAY);
        
        // Create milestones
        let milestones : [Types.Milestone] = [
            { percentage = 25; reached = false; reachedAt = null; reward = null },
            { percentage = 50; reached = false; reachedAt = null; reward = null },
            { percentage = 75; reached = false; reachedAt = null; reward = null },
            { percentage = 100; reached = false; reachedAt = null; reward = null }
        ];
        
        let goal : Types.SavingsGoal = {
            id = goalId;
            owner = caller;
            title = request.title;
            description = request.description;
            category = request.category;
            targetAmount = request.targetAmount;
            currentAmount = 0;
            unlockTime = unlockTime;
            createdAt = now;
            updatedAt = now;
            status = #Active;
            interestRate = DEFAULT_INTEREST_RATE;
            emergencyWithdrawalPenalty = request.emergencyWithdrawalPenalty;
            visibility = request.visibility;
            milestones = milestones;
            tags = request.tags;
            recurringDeposit = switch (request.recurringDeposit) {
                case (?setup) {
                    let nextTime = switch (setup.frequency) {
                        case (#Daily) { now + NANOSECONDS_PER_DAY };
                        case (#Weekly) { now + (7 * NANOSECONDS_PER_DAY) };
                        case (#BiWeekly) { now + (14 * NANOSECONDS_PER_DAY) };
                        case (#Monthly) { now + (30 * NANOSECONDS_PER_DAY) };
                        case (#Quarterly) { now + (90 * NANOSECONDS_PER_DAY) };
                    };
                    ?{
                        amount = setup.amount;
                        frequency = setup.frequency;
                        nextDepositTime = nextTime;
                        active = true;
                    }
                };
                case null { null };
            };
            contributors = [];
        };
        
        goals.put(goalId, goal);
        
        let existingGoals = switch (userGoals.get(caller)) {
            case null { [] };
            case (?g) { g };
        };
        userGoals.put(caller, Array.append(existingGoals, [goalId]));
        
        // Notify user
        ignore userMgmt.createNotification(
            caller,
            #GoalMilestone,
            "🎯 New goal created: " # request.title,
            null
        );
        
        #ok(goalId)
    };
    
    public shared(msg) func updateGoal(request: Types.UpdateGoalRequest) : async Types.UpdateGoalResult {
        let caller = msg.caller;
        
        let goal = switch (goals.get(request.goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Active) {
            return #err("Cannot update non-active goal");
        };
        
        let updatedGoal : Types.SavingsGoal = {
            goal with
            title = Option.get(request.title, goal.title);
            description = Option.get(request.description, goal.description);
            targetAmount = Option.get(request.targetAmount, goal.targetAmount);
            visibility = Option.get(request.visibility, goal.visibility);
            tags = Option.get(request.tags, goal.tags);
            updatedAt = Time.now();
        };
        
        goals.put(request.goalId, updatedGoal);
        #ok()
    };
    
    public shared(msg) func pauseGoal(goalId: Nat) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Active) {
            return #err("Goal is not active");
        };
        
        let updatedGoal = { goal with status = #Paused; updatedAt = Time.now() };
        goals.put(goalId, updatedGoal);
        #ok()
    };
    
    public shared(msg) func resumeGoal(goalId: Nat) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Paused) {
            return #err("Goal is not paused");
        };
        
        let updatedGoal = { goal with status = #Active; updatedAt = Time.now() };
        goals.put(goalId, updatedGoal);
        #ok()
    };
    
    public shared(msg) func cancelGoal(goalId: Nat) : async Result.Result<Nat, Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Active and goal.status != #Paused) {
            return #err("Can only cancel active or paused goals");
        };
        
        if (goal.currentAmount == 0) {
            let updatedGoal = { goal with status = #Cancelled; updatedAt = Time.now() };
            goals.put(goalId, updatedGoal);
            return #ok(0);
        };
        
        // Refund the amount (no interest, no penalty for cancellation)
        let ledger = actor(Principal.toText(ckBtcLedgerPrincipal)) : actor {
            icrc1_transfer : (Types.TransferArgs) -> async Types.TransferResult;
        };
        
        let transferResult = await ledger.icrc1_transfer({
            to = { owner = caller; subaccount = null };
            amount = goal.currentAmount;
            fee = null;
            memo = null;
            from_subaccount = null;
            created_at_time = null;
        });
        
        switch (transferResult) {
            case (#Err(e)) { return #err("Refund failed") };
            case (#Ok(blockIndex)) {
                let txId = createTransaction(
                    goalId,
                    caller,
                    #RefundIssued,
                    goal.currentAmount,
                    0,
                    ?blockIndex,
                    ?"Goal cancelled, funds refunded"
                );
                
                updateGlobalStats(Int.abs(goal.currentAmount), false);
                
                let updatedGoal = { goal with status = #Cancelled; updatedAt = Time.now() };
                goals.put(goalId, updatedGoal);
                
                #ok(goal.currentAmount)
            };
        }
    };
    
    // ============= DEPOSIT & WITHDRAWAL =============
    
    public shared(msg) func deposit(request: Types.DepositRequest) : async Types.DepositResult {
        let caller = msg.caller;
        
        let goal = switch (goals.get(request.goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Active) {
            return #err("Goal is not active");
        };
        
        if (request.amount == 0) {
            return #err("Deposit amount must be greater than 0");
        };
        
        let ledger = actor(Principal.toText(ckBtcLedgerPrincipal)) : actor {
            icrc2_transfer_from : (Types.TransferFromArgs) -> async Types.TransferResult;
        };
        
        let transferResult = await ledger.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = caller; subaccount = null };
            to = { owner = Principal.fromActor(this); subaccount = null };
            amount = request.amount;
            fee = null;
            memo = null;
            created_at_time = null;
        });
        
        switch (transferResult) {
            case (#Err(_)) { return #err("Transfer failed. Ensure you've approved the canister.") };
            case (#Ok(blockIndex)) {
                let newAmount = goal.currentAmount + request.amount;
                var updatedGoal = { goal with currentAmount = newAmount; updatedAt = Time.now() };
                updatedGoal := checkMilestones(updatedGoal);
                goals.put(request.goalId, updatedGoal);
                
                let txId = createTransaction(
                    request.goalId,
                    caller,
                    #Deposit,
                    request.amount,
                    0,
                    ?blockIndex,
                    request.message
                );
                
                updateGlobalStats(Int.abs(request.amount), true);
                
                // Update user stats
                let userTotalSaved = await calculateUserTotalSaved(caller);
                ignore userMgmt.updateUserStats(caller, userTotalSaved, 0, 0);
                ignore userMgmt.updateUserTier(caller, userTotalSaved);
                
                // Notify user
                ignore userMgmt.createNotification(
                    caller,
                    #DepositConfirmed,
                    "✅ Deposit confirmed: " # Nat.toText(request.amount) # " satoshis",
                    null
                );
                
                #ok(txId)
            };
        }
    };
    
    public shared(msg) func withdraw(request: Types.WithdrawalRequest) : async Types.WithdrawalResult {
        let caller = msg.caller;
        
        let goal = switch (goals.get(request.goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (goal.status != #Active) {
            return #err("Goal is not active");
        };
        
        if (goal.currentAmount == 0) {
            return #err("No funds to withdraw");
        };
        
        let now = Time.now();
        var withdrawAmount = goal.currentAmount;
        var penalty : Nat = 0;
        var interest : Nat = 0;
        let newStatus : Types.GoalStatus = if (request.isEmergency) {
            #EmergencyWithdrawn
        } else {
            #Withdrawn
        };
        
        let txType : Types.TransactionType = if (request.isEmergency) {
            #EmergencyWithdrawal
        } else {
            #Withdrawal
        };
        
        if (request.isEmergency) {
            penalty := (withdrawAmount * goal.emergencyWithdrawalPenalty) / BASIS_POINTS;
            withdrawAmount := withdrawAmount - penalty;
            totalInterestPool += penalty;
            totalPenaltiesCollected += penalty;
        } else {
            if (now < goal.unlockTime) {
                return #err("Goal is still locked. Use emergency withdrawal if needed.");
            };
            
            interest := calculateInterest(goal);
            if (interest > totalInterestPool) {
                interest := totalInterestPool;
            };
            withdrawAmount := withdrawAmount + interest;
            totalInterestPool -= interest;
            totalInterestPaid += interest;
        };
        
        let ledger = actor(Principal.toText(ckBtcLedgerPrincipal)) : actor {
            icrc1_transfer : (Types.TransferArgs) -> async Types.TransferResult;
        };
        
        let transferResult = await ledger.icrc1_transfer({
            to = { owner = caller; subaccount = null };
            amount = withdrawAmount;
            fee = null;
            memo = null;
            from_subaccount = null;
            created_at_time = null;
        });
        
        switch (transferResult) {
            case (#Err(_)) { return #err("Transfer failed") };
            case (#Ok(blockIndex)) {
                let txId = createTransaction(
                    request.goalId,
                    caller,
                    txType,
                    withdrawAmount,
                    penalty,
                    ?blockIndex,
                    if (request.isEmergency) { ?"Emergency withdrawal" } else { ?"Normal withdrawal" }
                );
                
                updateGlobalStats(Int.abs(goal.currentAmount), false);
                
                let updatedGoal = { goal with status = newStatus; updatedAt = Time.now() };
                goals.put(request.goalId, updatedGoal);
                
                // Update user stats
                ignore userMgmt.createNotification(
                    caller,
                    #WithdrawalProcessed,
                    "💰 Withdrawal processed: " # Nat.toText(withdrawAmount) # " satoshis",
                    null
                );
                
                #ok(withdrawAmount)
            };
        }
    };
    
    // ============= CONTRIBUTION (SOCIAL FEATURE) =============
    
    public shared(msg) func contributeToGoal(request: Types.ContributeRequest) : async Types.ContributeResult {
        let caller = msg.caller;
        
        let goal = switch (goals.get(request.goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner == caller) {
            return #err("Cannot contribute to your own goal. Use deposit instead.");
        };
        
        if (goal.status != #Active) {
            return #err("Goal is not active");
        };
        
        if (goal.visibility == #Private) {
            return #err("This goal is private");
        };
        
        if (request.amount == 0) {
            return #err("Contribution amount must be greater than 0");
        };
        
        let ledger = actor(Principal.toText(ckBtcLedgerPrincipal)) : actor {
            icrc2_transfer_from : (Types.TransferFromArgs) -> async Types.TransferResult;
        };
        
        let transferResult = await ledger.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = caller; subaccount = null };
            to = { owner = Principal.fromActor(this); subaccount = null };
            amount = request.amount;
            fee = null;
            memo = null;
            created_at_time = null;
        });
        
        switch (transferResult) {
            case (#Err(_)) { return #err("Transfer failed") };
            case (#Ok(blockIndex)) {
                let contributor : Types.Contributor = {
                    principal = caller;
                    amount = request.amount;
                    timestamp = Time.now();
                    message = request.message;
                };
                
                let newAmount = goal.currentAmount + request.amount;
                var updatedGoal = {
                    goal with
                    currentAmount = newAmount;
                    contributors = Array.append(goal.contributors, [contributor]);
                    updatedAt = Time.now();
                };
                updatedGoal := checkMilestones(updatedGoal);
                goals.put(request.goalId, updatedGoal);
                
                let txId = createTransaction(
                    request.goalId,
                    caller,
                    #ContributionReceived,
                    request.amount,
                    0,
                    ?blockIndex,
                    request.message
                );
                
                updateGlobalStats(Int.abs(request.amount), true);
                
                // Notify goal owner
                ignore userMgmt.createNotification(
                    goal.owner,
                    #ContributionReceived,
                    "🎁 Someone contributed " # Nat.toText(request.amount) # " satoshis to '" # goal.title # "'",
                    null
                );
                
                #ok(txId)
            };
        }
    };
    
    // ============= QUERY FUNCTIONS =============
    
    public query func getGoal(goalId: Nat) : async ?Types.SavingsGoal {
        goals.get(goalId)
    };
    
    public query func getUserGoals(user: Principal) : async [Types.SavingsGoal] {
        let goalIds = switch (userGoals.get(user)) {
            case null { [] };
            case (?ids) { ids };
        };
        
        let buffer = Buffer.Buffer<Types.SavingsGoal>(goalIds.size());
        for (id in goalIds.vals()) {
            switch (goals.get(id)) {
                case (?goal) { buffer.add(goal) };
                case null {};
            };
        };
        Buffer.toArray(buffer)
    };
    
    public query func getActiveGoals(user: Principal) : async [Types.SavingsGoal] {
        let goalIds = switch (userGoals.get(user)) {
            case null { [] };
            case (?ids) { ids };
        };
        
        let buffer = Buffer.Buffer<Types.SavingsGoal>(goalIds.size());
        for (id in goalIds.vals()) {
            switch (goals.get(id)) {
                case (?goal) {
                    if (goal.status == #Active) {
                        buffer.add(goal);
                    };
                };
                case null {};
            };
        };
        Buffer.toArray(buffer)
    };
    
    public query func getPublicGoals(limit: Nat, offset: Nat) : async [Types.SavingsGoal] {
        let buffer = Buffer.Buffer<Types.SavingsGoal>(limit);
        var count = 0;
        var skipped = 0;
        
        for ((_, goal) in goals.entries()) {
            if (count >= limit) { return Buffer.toArray(buffer) };
            
            if (goal.visibility == #Public and goal.status == #Active) {
                if (skipped >= offset) {
                    buffer.add(goal);
                    count += 1;
                } else {
                    skipped += 1;
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    public query func getUserStats(user: Principal) : async Types.UserStats {
        let goalIds = switch (userGoals.get(user)) {
            case null { [] };
            case (?ids) { ids };
        };
        
        var totalGoals = 0;
        var activeGoals = 0;
        var completedGoals = 0;
        var cancelledGoals = 0;
        var totalSaved = 0;
        var totalWithdrawn = 0;
        var totalInterestEarned = 0;
        var totalPenaltiesPaid = 0;
        var totalContributions = 0;
        var totalContributionsReceived = 0;
        var goalDurations = Buffer.Buffer<Int>(goalIds.size());
        
        for (id in goalIds.vals()) {
            switch (goals.get(id)) {
                case (?goal) {
                    totalGoals += 1;
                    
                    switch (goal.status) {
                        case (#Active) {
                            activeGoals += 1;
                            totalSaved += goal.currentAmount;
                        };
                        case (#Completed or #Withdrawn) {
                            completedGoals += 1;
                            let duration = goal.unlockTime - goal.createdAt;
                            goalDurations.add(duration);
                        };
                        case (#Cancelled) { cancelledGoals += 1 };
                        case (#Paused) { activeGoals += 1 };
                        case _ {};
                    };
                    
                    totalContributionsReceived += Array.foldLeft<Types.Contributor, Nat>(
                        goal.contributors, 0, func(acc, c) { acc + c.amount }
                    );
                };
                case null {};
            };
        };
        
        // Calculate average goal duration
        let avgGoalSize = if (activeGoalCount > 0) {
            totalGoalSize / activeGoalCount
        } else { 0 };
        
        // Find most popular category
        var maxCount = 0;
        var popularCategory : Types.GoalCategory = #Vacation;
        for ((cat, count) in activeCategoryCount.entries()) {
            if (count > maxCount) {
                maxCount := count;
            };
        };
        
        {
            totalUsers = totalUsers;
            totalGoals = totalGoalsCount;
            totalValueLocked = totalValueLocked;
            totalInterestPaid = totalInterestPaid;
            totalPenaltiesCollected = totalPenaltiesCollected;
            averageGoalSize = avgGoalSize;
            mostPopularCategory = popularCategory;
            totalTransactions = Iter.size(transactions.entries());
        }
    };
    
    public query func getProjectedInterest(goalId: Nat) : async ?Nat {
        switch (goals.get(goalId)) {
            case null { null };
            case (?goal) { ?calculateInterest(goal) };
        }
    };
    
    public query func getTransaction(txId: Nat) : async ?Types.Transaction {
        transactions.get(txId)
    };
    
    public query func getUserTransactions(user: Principal, limit: Nat) : async [Types.Transaction] {
        let txIds = switch (userTransactions.get(user)) {
            case null { [] };
            case (?ids) { ids };
        };
        
        let buffer = Buffer.Buffer<Types.Transaction>(limit);
        var count = 0;
        
        // Get most recent transactions
        let sorted = Array.sort<Nat>(txIds, func(a, b) {
            if (a > b) { #less } else if (a < b) { #greater } else { #equal }
        });
        
        for (id in sorted.vals()) {
            if (count >= limit) { return Buffer.toArray(buffer) };
            
            switch (transactions.get(id)) {
                case (?tx) {
                    buffer.add(tx);
                    count += 1;
                };
                case null {};
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    public query func getGoalTransactions(goalId: Nat) : async [Types.Transaction] {
        let buffer = Buffer.Buffer<Types.Transaction>(10);
        
        for ((_, tx) in transactions.entries()) {
            if (tx.goalId == goalId) {
                buffer.add(tx);
            };
        };
        
        // Sort by timestamp descending
        let sorted = Array.sort<Types.Transaction>(Buffer.toArray(buffer), func(a, b) {
            if (a.timestamp > b.timestamp) { #less }
            else if (a.timestamp < b.timestamp) { #greater }
            else { #equal }
        });
        
        sorted
    };
    
    public query func searchGoalsByCategory(category: Types.GoalCategory) : async [Types.SavingsGoal] {
        let buffer = Buffer.Buffer<Types.SavingsGoal>(10);
        
        for ((_, goal) in goals.entries()) {
            if (goal.category == category and goal.visibility == #Public and goal.status == #Active) {
                buffer.add(goal);
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    public query func searchGoalsByTag(tag: Text) : async [Types.SavingsGoal] {
        let buffer = Buffer.Buffer<Types.SavingsGoal>(10);
        
        for ((_, goal) in goals.entries()) {
            if (goal.visibility == #Public and goal.status == #Active) {
                let hasTag = Array.find<Text>(goal.tags, func(t) { t == tag });
                if (Option.isSome(hasTag)) {
                    buffer.add(goal);
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // ============= LEADERBOARD =============
    
    public query func getLeaderboard(leaderboardType: Types.LeaderboardType, limit: Nat) : async [Types.LeaderboardEntry] {
        let buffer = Buffer.Buffer<Types.LeaderboardEntry>(limit);
        var entries = Buffer.Buffer<(Principal, Nat)>(100);
        
        switch (leaderboardType) {
            case (#TotalSaved) {
                for ((user, goalIds) in userGoals.entries()) {
                    var total = 0;
                    for (id in goalIds.vals()) {
                        switch (goals.get(id)) {
                            case (?goal) {
                                if (goal.status == #Active) {
                                    total += goal.currentAmount;
                                };
                            };
                            case null {};
                        };
                    };
                    if (total > 0) {
                        entries.add((user, total));
                    };
                };
            };
            case (#MostGoals) {
                for ((user, goalIds) in userGoals.entries()) {
                    var count = 0;
                    for (id in goalIds.vals()) {
                        switch (goals.get(id)) {
                            case (?goal) {
                                if (goal.status == #Active or goal.status == #Completed) {
                                    count += 1;
                                };
                            };
                            case null {};
                        };
                    };
                    if (count > 0) {
                        entries.add((user, count));
                    };
                };
            };
            case (#LongestLock) {
                for ((user, goalIds) in userGoals.entries()) {
                    var maxDuration = 0;
                    for (id in goalIds.vals()) {
                        switch (goals.get(id)) {
                            case (?goal) {
                                if (goal.status == #Active) {
                                    let duration = Int.abs(goal.unlockTime - goal.createdAt);
                                    if (duration > maxDuration) {
                                        maxDuration := duration;
                                    };
                                };
                            };
                            case null {};
                        };
                    };
                    if (maxDuration > 0) {
                        entries.add((user, maxDuration));
                    };
                };
            };
            case (#HighestInterest) {
                for ((user, goalIds) in userGoals.entries()) {
                    var totalInterest = 0;
                    for (id in goalIds.vals()) {
                        switch (goals.get(id)) {
                            case (?goal) {
                                if (goal.status == #Active) {
                                    totalInterest += calculateInterest(goal);
                                };
                            };
                            case null {};
                        };
                    };
                    if (totalInterest > 0) {
                        entries.add((user, totalInterest));
                    };
                };
            };
        };
        
        // Sort entries
        let sorted = Array.sort<(Principal, Nat)>(Buffer.toArray(entries), func(a, b) {
            if (a.1 > b.1) { #less }
            else if (a.1 < b.1) { #greater }
            else { #equal }
        });
        
        // Create leaderboard entries
        var rank = 1;
        for (i in Iter.range(0, Nat.min(limit, sorted.size()) - 1)) {
            if (i < sorted.size()) {
                let (user, score) = sorted[i];
                buffer.add({
                    user = user;
                    username = null; // TODO: Fetch from user management
                    score = score;
                    rank = rank;
                });
                rank += 1;
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // ============= COMMENTS (SOCIAL FEATURE) =============
    
    public shared(msg) func addComment(goalId: Nat, comment: Text) : async Result.Result<Nat, Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.visibility == #Private) {
            return #err("Cannot comment on private goals");
        };
        
        if (Text.size(comment) == 0 or Text.size(comment) > 500) {
            return #err("Comment must be between 1 and 500 characters");
        };
        
        let existing = switch (goalComments.get(goalId)) {
            case null { [] };
            case (?c) { c };
        };
        
        let commentId = Array.size(existing);
        let newComment : Types.GoalComment = {
            id = commentId;
            goalId = goalId;
            author = caller;
            comment = comment;
            timestamp = Time.now();
            likes = 0;
        };
        
        goalComments.put(goalId, Array.append(existing, [newComment]));
        
        // Notify goal owner
        if (goal.owner != caller) {
            ignore userMgmt.createNotification(
                goal.owner,
                #SystemAlert,
                "💬 New comment on your goal '" # goal.title # "'",
                null
            );
        };
        
        #ok(commentId)
    };
    
    public query func getComments(goalId: Nat) : async [Types.GoalComment] {
        switch (goalComments.get(goalId)) {
            case null { [] };
            case (?c) { c };
        }
    };
    
    // ============= RECURRING DEPOSITS =============
    
    public shared(msg) func toggleRecurringDeposit(goalId: Nat, active: Bool) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        switch (goal.recurringDeposit) {
            case null { return #err("No recurring deposit configured") };
            case (?rd) {
                let updated = { rd with active = active };
                let updatedGoal = {
                    goal with
                    recurringDeposit = ?updated;
                    updatedAt = Time.now();
                };
                goals.put(goalId, updatedGoal);
                #ok()
            };
        }
    };
    
    public shared(msg) func updateRecurringDeposit(
        goalId: Nat,
        amount: Nat,
        frequency: Types.DepositFrequency
    ) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        let goal = switch (goals.get(goalId)) {
            case null { return #err("Goal not found") };
            case (?g) { g };
        };
        
        if (goal.owner != caller) {
            return #err("Not the goal owner");
        };
        
        if (amount == 0) {
            return #err("Amount must be greater than 0");
        };
        
        let now = Time.now();
        let nextTime = switch (frequency) {
            case (#Daily) { now + NANOSECONDS_PER_DAY };
            case (#Weekly) { now + (7 * NANOSECONDS_PER_DAY) };
            case (#BiWeekly) { now + (14 * NANOSECONDS_PER_DAY) };
            case (#Monthly) { now + (30 * NANOSECONDS_PER_DAY) };
            case (#Quarterly) { now + (90 * NANOSECONDS_PER_DAY) };
        };
        
        let updated : Types.RecurringDeposit = {
            amount = amount;
            frequency = frequency;
            nextDepositTime = nextTime;
            active = true;
        };
        
        let updatedGoal = {
            goal with
            recurringDeposit = ?updated;
            updatedAt = Time.now();
        };
        goals.put(goalId, updatedGoal);
        #ok()
    };
    
    // Process recurring deposits (should be called by a timer)
    public shared(msg) func processRecurringDeposits() : async () {
        let now = Time.now();
        
        for ((goalId, goal) in goals.entries()) {
            if (goal.status != #Active) { continue };
            
            switch (goal.recurringDeposit) {
                case null {};
                case (?rd) {
                    if (rd.active and now >= rd.nextDepositTime) {
                        // Try to process recurring deposit
                        let depositResult = await deposit({
                            goalId = goalId;
                            amount = rd.amount;
                            message = ?"Automatic recurring deposit";
                        });
                        
                        // Update next deposit time
                        let nextTime = switch (rd.frequency) {
                            case (#Daily) { now + NANOSECONDS_PER_DAY };
                            case (#Weekly) { now + (7 * NANOSECONDS_PER_DAY) };
                            case (#BiWeekly) { now + (14 * NANOSECONDS_PER_DAY) };
                            case (#Monthly) { now + (30 * NANOSECONDS_PER_DAY) };
                            case (#Quarterly) { now + (90 * NANOSECONDS_PER_DAY) };
                        };
                        
                        let updatedRd = { rd with nextDepositTime = nextTime };
                        let updatedGoal = {
                            goal with
                            recurringDeposit = ?updatedRd;
                            updatedAt = Time.now();
                        };
                        goals.put(goalId, updatedGoal);
                        
                        // Notify user of result
                        switch (depositResult) {
                            case (#ok(_)) {
                                ignore userMgmt.createNotification(
                                    goal.owner,
                                    #DepositConfirmed,
                                    "🔄 Recurring deposit successful: " # Nat.toText(rd.amount) # " satoshis",
                                    null
                                );
                            };
                            case (#err(e)) {
                                ignore userMgmt.createNotification(
                                    goal.owner,
                                    #RecurringDepositFailed,
                                    "❌ Recurring deposit failed: " # e,
                                    null
                                );
                            };
                        };
                    };
                };
            };
        };
    };
    
    // ============= HELPER QUERIES =============
    
    private func calculateUserTotalSaved(user: Principal) : async Nat {
        let goalIds = switch (userGoals.get(user)) {
            case null { return 0 };
            case (?ids) { ids };
        };
        
        var total = 0;
        for (id in goalIds.vals()) {
            switch (goals.get(id)) {
                case (?goal) {
                    if (goal.status == #Active or goal.status == #Paused) {
                        total += goal.currentAmount;
                    };
                };
                case null {};
            };
        };
        total
    };
    
    public query func getInterestPool() : async Nat {
        totalInterestPool
    };
    
    public query func getTotalValueLocked() : async Nat {
        totalValueLocked
    };
    
    public shared(msg) func fundInterestPool(amount: Nat) : async Types.DepositResult {
        let caller = msg.caller;
        
        if (amount == 0) {
            return #err("Amount must be greater than 0");
        };
        
        let ledger = actor(Principal.toText(ckBtcLedgerPrincipal)) : actor {
            icrc2_transfer_from : (Types.TransferFromArgs) -> async Types.TransferResult;
        };
        
        let transferResult = await ledger.icrc2_transfer_from({
            spender_subaccount = null;
            from = { owner = caller; subaccount = null };
            to = { owner = Principal.fromActor(this); subaccount = null };
            amount = amount;
            fee = null;
            memo = null;
            created_at_time = null;
        });
        
        switch (transferResult) {
            case (#Err(_)) { return #err("Transfer failed") };
            case (#Ok(blockIndex)) {
                totalInterestPool += amount;
                #ok(blockIndex)
            };
        }
    };
    
    public shared(msg) func setCkBtcLedger(ledger: Principal) : async () {
        // In production, add admin check here
        ckBtcLedgerPrincipal := ledger;
    };
    
    public query func getCkBtcLedger() : async Principal {
        ckBtcLedgerPrincipal
    };
}
Duration = if (goalDurations.size() > 0) {
            var sum : Int = 0;
            for (d in goalDurations.vals()) {
                sum += d;
            };
            sum / goalDurations.size()
        } else { 0 };
        
        {
            totalGoals = totalGoals;
            activeGoals = activeGoals;
            completedGoals = completedGoals;
            cancelledGoals = cancelledGoals;
            totalSaved = totalSaved;
            totalWithdrawn = totalWithdrawn;
            totalInterestEarned = totalInterestEarned;
            totalPenaltiesPaid = totalPenaltiesPaid;
            averageGoalDuration = avgDuration;
            longestStreak = 0; // TODO: Implement streak tracking
            currentStreak = 0;
            totalContributions = totalContributions;
            totalContributionsReceived = totalContributionsReceived;
        }
    };
    
    public query func getGlobalStats() : async Types.GlobalStats {
        let totalUsers = Iter.size(userGoals.entries());
        let totalGoalsCount = Iter.size(goals.entries());
        
        var activeCategoryCount = HashMap.HashMap<Text, Nat>(10, Text.equal, Text.hash);
        var totalGoalSize : Nat = 0;
        var activeGoalCount : Nat = 0;
        
        for ((_, goal) in goals.entries()) {
            if (goal.status == #Active) {
                activeGoalCount += 1;
                totalGoalSize += goal.targetAmount;
                
                let catName = debug_show(goal.category);
                let count = Option.get(activeCategoryCount.get(catName), 0);
                activeCategoryCount.put(catName, count + 1);
            };
        };
        
        let avg