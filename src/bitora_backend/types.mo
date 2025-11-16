// Types.mo - Comprehensive type definitions for Bitcoin Savings Lock

import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";

module {
    // ============= USER TYPES =============
    
    public type UserId = Principal;
    
    public type UserProfile = {
        id: UserId;
        username: ?Text;
        email: ?Text;
        avatar: ?Blob;
        createdAt: Time.Time;
        lastActive: Time.Time;
        preferences: UserPreferences;
        kycStatus: KYCStatus;
        tier: UserTier;
        totalSaved: Nat;
        totalWithdrawn: Nat;
        totalInterestEarned: Nat;
    };
    
    public type UserPreferences = {
        currency: Text; // USD, EUR, etc for display
        notifications: NotificationSettings;
        privacy: PrivacySettings;
        language: Text;
        timezone: Text;
    };
    
    public type NotificationSettings = {
        email: Bool;
        push: Bool;
        goalMilestones: Bool;
        depositConfirmations: Bool;
        withdrawalAlerts: Bool;
        interestUpdates: Bool;
    };
    
    public type PrivacySettings = {
        profileVisible: Bool;
        goalsVisible: Bool;
        statsVisible: Bool;
    };
    
    public type KYCStatus = {
        #NotStarted;
        #InProgress;
        #Approved;
        #Rejected: Text;
    };
    
    public type UserTier = {
        #Basic;      // 0-1 BTC total saved
        #Silver;     // 1-5 BTC total saved
        #Gold;       // 5-10 BTC total saved
        #Platinum;   // 10+ BTC total saved
    };
    
    // ============= GOAL TYPES =============
    
    public type GoalCategory = {
        #Vacation;
        #Education;
        #Emergency;
        #House;
        #Retirement;
        #Business;
        #Investment;
        #Wedding;
        #Medical;
        #Vehicle;
        #Custom: Text;
    };
    
    public type GoalStatus = {
        #Active;
        #Paused;
        #Completed;
        #Withdrawn;
        #EmergencyWithdrawn;
        #Cancelled;
    };
    
    public type GoalVisibility = {
        #Private;
        #Friends;
        #Public;
    };
    
    public type SavingsGoal = {
        id: Nat;
        owner: Principal;
        title: Text;
        description: Text;
        category: GoalCategory;
        targetAmount: Nat;
        currentAmount: Nat;
        unlockTime: Time.Time;
        createdAt: Time.Time;
        updatedAt: Time.Time;
        status: GoalStatus;
        interestRate: Nat;
        emergencyWithdrawalPenalty: Nat;
        visibility: GoalVisibility;
        milestones: [Milestone];
        tags: [Text];
        recurringDeposit: ?RecurringDeposit;
        contributors: [Contributor];
    };
    
    public type Milestone = {
        percentage: Nat; // 25, 50, 75, 100
        reached: Bool;
        reachedAt: ?Time.Time;
        reward: ?Nat; // Bonus interest or tokens
    };
    
    public type RecurringDeposit = {
        amount: Nat;
        frequency: DepositFrequency;
        nextDepositTime: Time.Time;
        active: Bool;
    };
    
    public type DepositFrequency = {
        #Daily;
        #Weekly;
        #BiWeekly;
        #Monthly;
        #Quarterly;
    };
    
    public type Contributor = {
        principal: Principal;
        amount: Nat;
        timestamp: Time.Time;
        message: ?Text;
    };
    
    // ============= TRANSACTION TYPES =============
    
    public type TransactionType = {
        #Deposit;
        #Withdrawal;
        #EmergencyWithdrawal;
        #InterestPayout;
        #PenaltyCharge;
        #RecurringDeposit;
        #ContributionReceived;
        #RefundIssued;
    };
    
    public type Transaction = {
        id: Nat;
        goalId: Nat;
        user: Principal;
        txType: TransactionType;
        amount: Nat;
        fee: Nat;
        timestamp: Time.Time;
        blockIndex: ?Nat;
        status: TransactionStatus;
        memo: ?Text;
    };
    
    public type TransactionStatus = {
        #Pending;
        #Completed;
        #Failed: Text;
    };
    
    // ============= ANALYTICS TYPES =============
    
    public type UserStats = {
        totalGoals: Nat;
        activeGoals: Nat;
        completedGoals: Nat;
        cancelledGoals: Nat;
        totalSaved: Nat;
        totalWithdrawn: Nat;
        totalInterestEarned: Nat;
        totalPenaltiesPaid: Nat;
        averageGoalDuration: Int;
        longestStreak: Nat; // Days with active goals
        currentStreak: Nat;
        totalContributions: Nat;
        totalContributionsReceived: Nat;
    };
    
    public type GlobalStats = {
        totalUsers: Nat;
        totalGoals: Nat;
        totalValueLocked: Nat;
        totalInterestPaid: Nat;
        totalPenaltiesCollected: Nat;
        averageGoalSize: Nat;
        mostPopularCategory: GoalCategory;
        totalTransactions: Nat;
    };
    
    public type LeaderboardEntry = {
        user: Principal;
        username: ?Text;
        score: Nat;
        rank: Nat;
    };
    
    public type LeaderboardType = {
        #TotalSaved;
        #LongestLock;
        #MostGoals;
        #HighestInterest;
    };
    
    // ============= REQUEST TYPES =============
    
    public type CreateGoalRequest = {
        title: Text;
        description: Text;
        category: GoalCategory;
        targetAmount: Nat;
        lockDurationDays: Nat;
        emergencyWithdrawalPenalty: Nat;
        visibility: GoalVisibility;
        tags: [Text];
        recurringDeposit: ?RecurringDepositSetup;
    };
    
    public type RecurringDepositSetup = {
        amount: Nat;
        frequency: DepositFrequency;
    };
    
    public type UpdateGoalRequest = {
        goalId: Nat;
        title: ?Text;
        description: ?Text;
        targetAmount: ?Nat;
        visibility: ?GoalVisibility;
        tags: ?[Text];
    };
    
    public type DepositRequest = {
        goalId: Nat;
        amount: Nat;
        message: ?Text;
    };
    
    public type WithdrawalRequest = {
        goalId: Nat;
        isEmergency: Bool;
    };
    
    public type ContributeRequest = {
        goalId: Nat;
        amount: Nat;
        message: ?Text;
    };
    
    public type UpdateProfileRequest = {
        username: ?Text;
        email: ?Text;
        avatar: ?Blob;
        preferences: ?UserPreferences;
    };
    
    // ============= RESULT TYPES =============
    
    public type Result<T, E> = {
        #ok: T;
        #err: E;
    };
    
    public type CreateGoalResult = Result<Nat, Text>;
    public type UpdateGoalResult = Result<(), Text>;
    public type DepositResult = Result<Nat, Text>; // Returns transaction ID
    public type WithdrawalResult = Result<Nat, Text>; // Returns amount withdrawn
    public type ContributeResult = Result<Nat, Text>;
    public type UpdateProfileResult = Result<(), Text>;
    
    // ============= NOTIFICATION TYPES =============
    
    public type Notification = {
        id: Nat;
        user: Principal;
        notifType: NotificationType;
        message: Text;
        timestamp: Time.Time;
        read: Bool;
        actionUrl: ?Text;
    };
    
    public type NotificationType = {
        #GoalMilestone;
        #DepositConfirmed;
        #WithdrawalProcessed;
        #InterestEarned;
        #GoalUnlocked;
        #ContributionReceived;
        #RecurringDepositFailed;
        #SystemAlert;
    };
    
    // ============= GOVERNANCE TYPES =============
    
    public type Proposal = {
        id: Nat;
        proposer: Principal;
        title: Text;
        description: Text;
        proposalType: ProposalType;
        createdAt: Time.Time;
        votingEndsAt: Time.Time;
        status: ProposalStatus;
        votesFor: Nat;
        votesAgainst: Nat;
        executed: Bool;
    };
    
    public type ProposalType = {
        #ChangeInterestRate: Nat;
        #ChangePenaltyRate: Nat;
        #AddFeature: Text;
        #UpdateProtocol: Text;
    };
    
    public type ProposalStatus = {
        #Active;
        #Passed;
        #Rejected;
        #Executed;
    };
    
    public type Vote = {
        proposalId: Nat;
        voter: Principal;
        vote: Bool; // true = for, false = against
        votingPower: Nat;
        timestamp: Time.Time;
    };
    
    // ============= ICRC TYPES =============
    
    public type Account = {
        owner: Principal;
        subaccount: ?Blob;
    };
    
    public type ApproveArgs = {
        spender: Account;
        amount: Nat;
        expires_at: ?Nat64;
        fee: ?Nat;
        memo: ?Blob;
        from_subaccount: ?Blob;
        created_at_time: ?Nat64;
    };
    
    public type TransferArgs = {
        to: Account;
        amount: Nat;
        fee: ?Nat;
        memo: ?Blob;
        from_subaccount: ?Blob;
        created_at_time: ?Nat64;
    };
    
    public type TransferFromArgs = {
        spender_subaccount: ?Blob;
        from: Account;
        to: Account;
        amount: Nat;
        fee: ?Nat;
        memo: ?Blob;
        created_at_time: ?Nat64;
    };
    
    public type TransferResult = {
        #Ok: Nat;
        #Err: TransferError;
    };
    
    public type TransferError = {
        #BadFee: { expected_fee: Nat };
        #BadBurn: { min_burn_amount: Nat };
        #InsufficientFunds: { balance: Nat };
        #TooOld;
        #CreatedInFuture: { ledger_time: Nat64 };
        #Duplicate: { duplicate_of: Nat };
        #TemporarilyUnavailable;
        #GenericError: { error_code: Nat; message: Text };
    };
    
    // ============= SOCIAL TYPES =============
    
    public type SocialConnection = {
        user: Principal;
        connectedAt: Time.Time;
        sharedGoals: [Nat];
    };
    
    public type GoalComment = {
        id: Nat;
        goalId: Nat;
        author: Principal;
        comment: Text;
        timestamp: Time.Time;
        likes: Nat;
    };
    
    public type Achievement = {
        id: Nat;
        name: Text;
        description: Text;
        icon: Text;
        unlockedAt: Time.Time;
    };
}