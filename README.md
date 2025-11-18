# Bitcoin Savings Lock 🔒💰
Encode Bitcoin Hackathon

A comprehensive decentralized savings platform built on the Internet Computer that uses ckBTC (chain-key Bitcoin) to help users achieve their financial goals through time-locked savings, social features, governance, and advanced analytics.

## 🌟 Features

### Core Features
✅ **Time-Locked Savings** - Lock your ckBTC until a specific date  
✅ **Goal-Based Savings** - Create multiple goals with categories  
✅ **Interest Earnings** - Earn interest on locked funds (5% APY default)  
✅ **Emergency Withdrawals** - Access funds early with penalty fee  
✅ **Recurring Deposits** - Automate your savings  
✅ **Milestones & Rewards** - Track progress and earn bonuses  

### Social Features
✅ **Public Goals** - Share goals and receive contributions  
✅ **Comments & Likes** - Engage with the community  
✅ **Leaderboards** - Compete with other savers  
✅ **Friend Connections** - Connect with other users  
✅ **Achievements** - Unlock badges and rewards  

### Advanced Features
✅ **DAO Governance** - Vote on protocol changes  
✅ **Analytics Dashboard** - Track trends and metrics  
✅ **User Tiers** - Unlock benefits as you save more  
✅ **Notifications** - Stay updated on your goals  
✅ **Multi-Language** - Support for multiple languages  

## 🏗️ Architecture

### Canister System

```
┌─────────────────────────────────────────────────────────────┐
│                    Bitcoin Savings Lock                      │
├─────────────────────────────────────────────────────────────┤
│                                                               
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │     User     │    │   Savings    │    │  Analytics   │  │
│  │  Management  │◄───┤     Lock     │───►│              │  │
│  │              │    │  (Main Core) │    │              │  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘  │
│         │                    │                               
│         │                    │                               
│  ┌──────▼───────┐    ┌──────▼───────┐                      │
│  │  Governance  │    │    ckBTC     │                       │
│  │   (DAO)      │    │    Ledger    │                       │
│  │              │    │  (External)  │                       │
│  └──────────────┘    └──────────────┘                       │
│                                                               
└─────────────────────────────────────────────────────────────┘
```

### Canisters

1. **User Management** - User profiles, notifications, achievements, social connections
2. **Savings Lock** - Core savings logic, deposits, withdrawals, goals
3. **Analytics** - Metrics tracking, reporting, data visualization
4. **Governance** - DAO proposals, voting, protocol changes

### External Dependencies
- **ckBTC Ledger** (ICRC-2) - Chain-key Bitcoin token for deposits/withdrawals

## 🚀 Quick Start

### Prerequisites

```bash
# Install dfx
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"

# Verify installation
dfx --version
```

### Local Development

```bash
# 1. Clone the repository
git clone <your-repo>
cd bitcoin-savings-lock

# 2. Create directory structure
mkdir -p src
mkdir -p scripts

# Copy all .mo files to src/
# Copy scripts to scripts/

# 3. Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/test-workflow.sh

# 4. Deploy all canisters
./scripts/deploy.sh local

# 5. Test the system
./scripts/test-workflow.sh
```

### Mainnet Deployment

```bash
# Deploy to Internet Computer mainnet
./scripts/deploy.sh ic

# Note: Requires cycles for mainnet deployment
```

## 📚 Complete API Reference

### User Management Canister

#### Profile Management
```motoko
// Create or get user profile
getOrCreateProfile() : async UserProfile

// Update profile
updateProfile(request: UpdateProfileRequest) : async UpdateProfileResult

// Get profile by principal
getProfile(user: Principal) : async ?UserProfile

// Get profile by username
getProfileByUsername(username: Text) : async ?UserProfile

// Search users
searchUsers(prefix: Text, limit: Nat) : async [UserProfile]
```

#### Notifications
```motoko
// Create notification
createNotification(user: Principal, type: NotificationType, message: Text, actionUrl: ?Text) : async Nat

// Get notifications
getNotifications(user: Principal, limit: Nat) : async [Notification]

// Get unread count
getUnreadCount(user: Principal) : async Nat

// Mark as read
markNotificationRead(notifId: Nat) : async Bool

// Mark all as read
markAllNotificationsRead() : async ()
```

#### Achievements
```motoko
// Get achievements
getAchievements(user: Principal) : async [Achievement]
```

#### Social
```motoko
// Add connection
addConnection(friendPrincipal: Principal) : async Result<(), Text>

// Remove connection
removeConnection(friendPrincipal: Principal) : async ()

// Get connections
getConnections(user: Principal) : async [SocialConnection]
```

### Savings Lock Canister

#### Goal Management
```motoko
// Create goal
createGoal(request: CreateGoalRequest) : async CreateGoalResult

// Update goal
updateGoal(request: UpdateGoalRequest) : async UpdateGoalResult

// Pause goal
pauseGoal(goalId: Nat) : async Result<(), Text>

// Resume goal
resumeGoal(goalId: Nat) : async Result<(), Text>

// Cancel goal (with refund)
cancelGoal(goalId: Nat) : async Result<Nat, Text>

// Get goal
getGoal(goalId: Nat) : async ?SavingsGoal

// Get user goals
getUserGoals(user: Principal) : async [SavingsGoal]

// Get active goals
getActiveGoals(user: Principal) : async [SavingsGoal]

// Get public goals
getPublicGoals(limit: Nat, offset: Nat) : async [SavingsGoal]
```

#### Deposits & Withdrawals
```motoko
// Deposit ckBTC
deposit(request: DepositRequest) : async DepositResult

// Withdraw
withdraw(request: WithdrawalRequest) : async WithdrawalResult

// Contribute to someone's goal
contributeToGoal(request: ContributeRequest) : async ContributeResult
```

#### Recurring Deposits
```motoko
// Toggle recurring deposit
toggleRecurringDeposit(goalId: Nat, active: Bool) : async Result<(), Text>

// Update recurring deposit
updateRecurringDeposit(goalId: Nat, amount: Nat, frequency: DepositFrequency) : async Result<(), Text>

// Process recurring deposits (admin/timer)
processRecurringDeposits() : async ()
```

#### Transactions
```motoko
// Get transaction
getTransaction(txId: Nat) : async ?Transaction

// Get user transactions
getUserTransactions(user: Principal, limit: Nat) : async [Transaction]

// Get goal transactions
getGoalTransactions(goalId: Nat) : async [Transaction]
```

#### Statistics
```motoko
// Get user stats
getUserStats(user: Principal) : async UserStats

// Get global stats
getGlobalStats() : async GlobalStats

// Get projected interest
getProjectedInterest(goalId: Nat) : async ?Nat

// Get interest pool
getInterestPool() : async Nat

// Get total value locked
getTotalValueLocked() : async Nat
```

#### Search & Discovery
```motoko
// Search by category
searchGoalsByCategory(category: GoalCategory) : async [SavingsGoal]

// Search by tag
searchGoalsByTag(tag: Text) : async [SavingsGoal]
```

#### Leaderboards
```motoko
// Get leaderboard
getLeaderboard(type: LeaderboardType, limit: Nat) : async [LeaderboardEntry]
```

#### Comments (Social)
```motoko
// Add comment
addComment(goalId: Nat, comment: Text) : async Result<Nat, Text>

// Get comments
getComments(goalId: Nat) : async [GoalComment]
```

#### Admin Functions
```motoko
// Fund interest pool
fundInterestPool(amount: Nat) : async DepositResult

// Set ckBTC ledger
setCkBtcLedger(ledger: Principal) : async ()
```

### Analytics Canister

```motoko
// Get TVL history
getTVLHistory(days: Nat) : async [TimeSeriesData]

// Get deposit/withdrawal flows
getFlowHistory(days: Nat) : async { deposits: [TimeSeriesData]; withdrawals: [TimeSeriesData] }

// Get category distribution
getCategoryDistribution() : async [CategoryDistribution]

// Get active users history
getActiveUsersHistory(days: Nat) : async [TimeSeriesData]

// Get new goals history
getNewGoalsHistory(days: Nat) : async [TimeSeriesData]

// Calculate growth rates
calculateGrowthRate(days: Nat) : async { tvlGrowth: Float; userGrowth: Float; goalGrowth: Float }

// Get retention metrics
getRetentionMetrics() : async { dailyActiveUsers: Nat; weeklyActiveUsers: Nat; monthlyActiveUsers: Nat; dau_mau_ratio: Float }

// Get comparative metrics
getComparativeMetrics() : async { vsLastWeek: {...}; vsLastMonth: {...} }

// Generate monthly report
generateMonthlyReport(month: Nat, year: Nat) : async ?MonthlyReport
```

### Governance Canister

```motoko
// Create proposal
createProposal(title: Text, description: Text, proposalType: ProposalType) : async Result<Nat, Text>

// Vote on proposal
vote(proposalId: Nat, support: Bool) : async Result<(), Text>

// Finalize proposal
finalizeProposal(proposalId: Nat) : async Result<(), Text>

// Execute proposal
executeProposal(proposalId: Nat) : async Result<(), Text>

// Get proposal
getProposal(proposalId: Nat) : async ?Proposal

// Get all proposals
getAllProposals(status: ?ProposalStatus, limit: Nat, offset: Nat) : async [Proposal]

// Get active proposals
getActiveProposals() : async [Proposal]

// Get proposal votes
getProposalVotes(proposalId: Nat) : async [Vote]

// Get user votes
getUserVotes(user: Principal) : async [Nat]

// Get proposal stats
getProposalStats(proposalId: Nat) : async ?{ ... }

// Get governance parameters
getGovernanceParams() : async { ... }
```

## �� Usage Examples

### Complete Workflow Example

```bash
# 1. Create user profile
dfx canister call user_management getOrCreateProfile

# 2. Update profile
dfx canister call user_management updateProfile (
  record {
    username = opt "satoshi_saver";
    email = opt "satoshi@example.com";
    avatar = null;
    preferences = opt record {
      currency = "USD";
      notifications = record {
        email = true;
        push = true;
        goalMilestones = true;
        depositConfirmations = true;
        withdrawalAlerts = true;
        interestUpdates = true;
      };
      privacy = record {
        profileVisible = true;
        goalsVisible = true;
        statsVisible = true;
      };
      language = "en";
      timezone = "UTC";
    };
  }
)

# 3. Create a savings goal with recurring deposit
dfx canister call savings_lock createGoal (
  record {
    title = "Dream Vacation 2026";
    description = "Saving for a trip to Japan";
    category = variant { Vacation };
    targetAmount = 50_000_000;
    lockDurationDays = 365;
    emergencyWithdrawalPenalty = 1000;
    visibility = variant { Public };
    tags = vec { "travel"; "japan"; "2026" };
    recurringDeposit = opt record {
      amount = 1_000_000;
      frequency = variant { Monthly };
    };
  }
)

# 4. Approve ckBTC spending
dfx canister call mxzaz-hqaaa-aaaar-qaada-cai icrc2_approve (
  record {
    spender = record {
      owner = principal "YOUR_SAVINGS_CANISTER_ID";
      subaccount = null;
    };
    amount = 50_000_000;
    expires_at = null;
    memo = null;
    from_subaccount = null;
    created_at_time = null;
  }
)

# 5. Make first deposit
dfx canister call savings_lock deposit (
  record {
    goalId = 0;
    amount = 10_000_000;
    message = opt "First deposit!";
  }
)

# 6. Check progress
dfx canister call savings_lock getGoal '(0)'

# 7. View your stats
dfx canister call savings_lock getUserStats "(principal \"YOUR_PRINCIPAL\")"

# 8. Check projected interest
dfx canister call savings_lock getProjectedInterest '(0)'

# 9. View leaderboard
dfx canister call savings_lock getLeaderboard '(variant { TotalSaved }, 10)'

# 10. Create a governance proposal
dfx canister call governance createProposal (
  "Increase Interest Rate",
  "Proposal to increase base interest rate from 5% to 6% APY",
  variant { ChangeInterestRate = 600 }
)

# 11. Vote on proposal
dfx canister call governance vote '(0, true)'

# 12. Check notifications
dfx canister call user_management getNotifications "(principal \"YOUR_PRINCIPAL\", 10)"
```

## 🎨 Frontend Integration

### React Example

```typescript
import { Actor, HttpAgent } from '@dfinity/agent';
import { idlFactory } from './declarations/savings_lock';

const agent = new HttpAgent({ host: 'https://ic0.app' });
const savingsActor = Actor.createActor(idlFactory, {
  agent,
  canisterId: 'YOUR_CANISTER_ID',
});

// Create a goal
async function createGoal() {
  const result = await savingsActor.createGoal({
    title: 'My Goal',
    description: 'Saving for something',
    category: { Vacation: null },
    targetAmount: 10_000_000n,
    lockDurationDays: 90n,
    emergencyWithdrawalPenalty: 1000n,
    visibility: { Private: null },
    tags: [],
    recurringDeposit: [],
  });
  
  if ('ok' in result) {
    console.log('Goal created:', result.ok);
  } else {
    console.error('Error:', result.err);
  }
}

// Get user goals
async function getUserGoals(principal) {
  const goals = await savingsActor.getUserGoals(principal);
  return goals;
}
```

## 🧪 Testing

### Run Integration Tests

```bash
# Start local replica
dfx start --clean --background

# Deploy all canisters
./scripts/deploy.sh local

# Run tests
./scripts/test-workflow.sh
```

### Manual Testing Checklist

- [ ] Create user profile
- [ ] Create savings goal
- [ ] Deposit ckBTC
- [ ] Check milestones
- [ ] Withdraw funds (after lock period)
- [ ] Test emergency withdrawal
- [ ] Create recurring deposit
- [ ] Contribute to public goal
- [ ] Add comments
- [ ] Create governance proposal
- [ ] Vote on proposal
- [ ] Check analytics

## 📊 Data Models

### User Profile
```motoko
type UserProfile = {
  id: Principal;
  username: ?Text;
  email: ?Text;
  createdAt: Time;
  tier: UserTier;
  totalSaved: Nat;
  // ...
}
```

### Savings Goal
```motoko
type SavingsGoal = {
  id: Nat;
  owner: Principal;
  title: Text;
  targetAmount: Nat;
  currentAmount: Nat;
  unlockTime: Time;
  status: GoalStatus;
  milestones: [Milestone];
  // ...
}
```

## 🔒 Security

### Smart Contract Security
- ✅ Non-custodial design
- ✅ ICRC-2 approval-based transfers
- ✅ Time-lock enforcement
- ✅ Input validation
- ✅ Access control

### Best Practices
1. Always test with small amounts first
2. Verify canister IDs before approving
3. Keep emergency withdrawal penalties reasonable
4. Monitor your notifications
5. Participate in governance

## 🗺️ Roadmap

### Phase 1 ✅ (Current)
- Core savings functionality
- User management
- Analytics
- Governance

### Phase 2 🚧 (In Progress)
- Frontend application
- Mobile app
- Enhanced social features
- Advanced analytics dashboard

### Phase 3 📋 (Planned)
- Multi-asset support (ckETH, ckUSDC)
- DeFi integrations
- Insurance options
- Savings circles/groups
- Automated tax reporting

### Phase 4 🔮 (Future)
- Cross-chain bridges
- AI-powered savings recommendations
- Institutional features
- White-label solutions

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

## 📄 License

MIT License - see LICENSE file

## 🆘 Support

- **Documentation**: Full API docs above
- **Forum**: https://forum.dfinity.org
- **Discord**: https://discord.gg/internetcomputer
- **Issues**: [GitHub Issues]

## 🎓 Learn More

- [Internet Computer Docs](https://internetcomputer.org/docs)
- [Motoko Programming Guide](https://internetcomputer.org/docs/motoko/main/motoko)
- [ckBTC Documentation](https://internetcomputer.org/docs/current/developer-docs/integrations/bitcoin/ckbtc)
- [ICRC-2 Standard](https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-2)

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always test with small amounts first. Not financial advice.

---

**Built with ❤️ on the Internet Computer**

*Lock it, grow it, achieve it! 🚀*