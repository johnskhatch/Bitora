// UserManagement.mo - User Profile and Management Canister

import Types "./Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Nat "mo:base/Nat";

actor UserManagement {
    
    // ============= STATE =============
    
    private stable var nextUserId : Nat = 0;
    private stable var nextNotificationId : Nat = 0;
    private stable var nextAchievementId : Nat = 0;
    
    private var users = HashMap.HashMap<Principal, Types.UserProfile>(100, Principal.equal, Principal.hash);
    private var usernames = HashMap.HashMap<Text, Principal>(100, Text.equal, Text.hash);
    private var notifications = HashMap.HashMap<Principal, [Types.Notification]>(100, Principal.equal, Principal.hash);
    private var achievements = HashMap.HashMap<Principal, [Types.Achievement]>(100, Principal.equal, Principal.hash);
    private var socialConnections = HashMap.HashMap<Principal, [Types.SocialConnection]>(100, Principal.equal, Principal.hash);
    
    // Stable storage for upgrades
    private stable var usersEntries : [(Principal, Types.UserProfile)] = [];
    private stable var usernamesEntries : [(Text, Principal)] = [];
    private stable var notificationsEntries : [(Principal, [Types.Notification])] = [];
    private stable var achievementsEntries : [(Principal, [Types.Achievement])] = [];
    private stable var socialConnectionsEntries : [(Principal, [Types.SocialConnection])] = [];
    
    system func preupgrade() {
        usersEntries := Iter.toArray(users.entries());
        usernamesEntries := Iter.toArray(usernames.entries());
        notificationsEntries := Iter.toArray(notifications.entries());
        achievementsEntries := Iter.toArray(achievements.entries());
        socialConnectionsEntries := Iter.toArray(socialConnections.entries());
    };
    
    system func postupgrade() {
        users := HashMap.fromIter<Principal, Types.UserProfile>(usersEntries.vals(), 100, Principal.equal, Principal.hash);
        usernames := HashMap.fromIter<Text, Principal>(usernamesEntries.vals(), 100, Text.equal, Text.hash);
        notifications := HashMap.fromIter<Principal, [Types.Notification]>(notificationsEntries.vals(), 100, Principal.equal, Principal.hash);
        achievements := HashMap.fromIter<Principal, [Types.Achievement]>(achievementsEntries.vals(), 100, Principal.equal, Principal.hash);
        socialConnections := HashMap.fromIter<Principal, [Types.SocialConnection]>(socialConnectionsEntries.vals(), 100, Principal.equal, Principal.hash);
        
        usersEntries := [];
        usernamesEntries := [];
        notificationsEntries := [];
        achievementsEntries := [];
        socialConnectionsEntries := [];
    };
    
    // ============= USER PROFILE MANAGEMENT =============
    
    // Create or get user profile
    public shared(msg) func getOrCreateProfile() : async Types.UserProfile {
        let caller = msg.caller;
        
        switch (users.get(caller)) {
            case (?profile) {
                // Update last active
                let updatedProfile = {
                    profile with
                    lastActive = Time.now();
                };
                users.put(caller, updatedProfile);
                updatedProfile
            };
            case null {
                // Create new profile
                let now = Time.now();
                let newProfile : Types.UserProfile = {
                    id = caller;
                    username = null;
                    email = null;
                    avatar = null;
                    createdAt = now;
                    lastActive = now;
                    preferences = {
                        currency = "USD";
                        notifications = {
                            email = true;
                            push = true;
                            goalMilestones = true;
                            depositConfirmations = true;
                            withdrawalAlerts = true;
                            interestUpdates = true;
                        };
                        privacy = {
                            profileVisible = true;
                            goalsVisible = false;
                            statsVisible = false;
                        };
                        language = "en";
                        timezone = "UTC";
                    };
                    kycStatus = #NotStarted;
                    tier = #Basic;
                    totalSaved = 0;
                    totalWithdrawn = 0;
                    totalInterestEarned = 0;
                };
                users.put(caller, newProfile);
                newProfile
            };
        }
    };
    
    // Update user profile
    public shared(msg) func updateProfile(request: Types.UpdateProfileRequest) : async Types.UpdateProfileResult {
        let caller = msg.caller;
        
        let profile = switch (users.get(caller)) {
            case null { return #err("Profile not found. Call getOrCreateProfile first.") };
            case (?p) { p };
        };
        
        // Check if username is taken
        switch (request.username) {
            case (?newUsername) {
                if (Text.size(newUsername) < 3) {
                    return #err("Username must be at least 3 characters");
                };
                if (Text.size(newUsername) > 20) {
                    return #err("Username must be at most 20 characters");
                };
                
                // Check if username exists and belongs to someone else
                switch (usernames.get(newUsername)) {
                    case (?existingUser) {
                        if (existingUser != caller) {
                            return #err("Username already taken");
                        };
                    };
                    case null {
                        // Remove old username mapping if exists
                        switch (profile.username) {
                            case (?oldUsername) { usernames.delete(oldUsername) };
                            case null {};
                        };
                        usernames.put(newUsername, caller);
                    };
                };
            };
            case null {};
        };
        
        let updatedProfile : Types.UserProfile = {
            profile with
            username = Option.get(request.username, profile.username);
            email = Option.get(request.email, profile.email);
            avatar = Option.get(request.avatar, profile.avatar);
            preferences = Option.get(request.preferences, profile.preferences);
            lastActive = Time.now();
        };
        
        users.put(caller, updatedProfile);
        #ok()
    };
    
    // Get user profile by principal
    public query func getProfile(user: Principal) : async ?Types.UserProfile {
        users.get(user)
    };
    
    // Get user profile by username
    public query func getProfileByUsername(username: Text) : async ?Types.UserProfile {
        switch (usernames.get(username)) {
            case (?principal) { users.get(principal) };
            case null { null };
        }
    };
    
    // Search users by username prefix
    public query func searchUsers(prefix: Text, limit: Nat) : async [Types.UserProfile] {
        let buffer = Buffer.Buffer<Types.UserProfile>(limit);
        var count = 0;
        
        for ((username, principal) in usernames.entries()) {
            if (count >= limit) { return Buffer.toArray(buffer) };
            
            if (Text.startsWith(username, #text prefix)) {
                switch (users.get(principal)) {
                    case (?profile) {
                        if (profile.preferences.privacy.profileVisible) {
                            buffer.add(profile);
                            count += 1;
                        };
                    };
                    case null {};
                };
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    // Update user tier based on total saved
    public shared(msg) func updateUserTier(user: Principal, totalSaved: Nat) : async () {
        switch (users.get(user)) {
            case (?profile) {
                let newTier : Types.UserTier = if (totalSaved >= 1_000_000_000) {
                    #Platinum // 10+ BTC
                } else if (totalSaved >= 500_000_000) {
                    #Gold // 5+ BTC
                } else if (totalSaved >= 100_000_000) {
                    #Silver // 1+ BTC
                } else {
                    #Basic
                };
                
                let updatedProfile = {
                    profile with
                    tier = newTier;
                    totalSaved = totalSaved;
                };
                users.put(user, updatedProfile);
            };
            case null {};
        };
    };
    
    // Update user stats
    public shared(msg) func updateUserStats(
        user: Principal,
        totalSaved: Nat,
        totalWithdrawn: Nat,
        totalInterestEarned: Nat
    ) : async () {
        switch (users.get(user)) {
            case (?profile) {
                let updatedProfile = {
                    profile with
                    totalSaved = totalSaved;
                    totalWithdrawn = totalWithdrawn;
                    totalInterestEarned = totalInterestEarned;
                };
                users.put(user, updatedProfile);
                
                // Check for achievements
                await checkAndAwardAchievements(user, updatedProfile);
            };
            case null {};
        };
    };
    
    // ============= NOTIFICATIONS =============
    
    // Create notification
    public shared(msg) func createNotification(
        user: Principal,
        notifType: Types.NotificationType,
        message: Text,
        actionUrl: ?Text
    ) : async Nat {
        let notifId = nextNotificationId;
        nextNotificationId += 1;
        
        let notification : Types.Notification = {
            id = notifId;
            user = user;
            notifType = notifType;
            message = message;
            timestamp = Time.now();
            read = false;
            actionUrl = actionUrl;
        };
        
        let existing = switch (notifications.get(user)) {
            case null { [] };
            case (?n) { n };
        };
        
        notifications.put(user, Array.append(existing, [notification]));
        notifId
    };
    
    // Get user notifications
    public query func getNotifications(user: Principal, limit: Nat) : async [Types.Notification] {
        switch (notifications.get(user)) {
            case null { [] };
            case (?notifs) {
                let sorted = Array.sort<Types.Notification>(notifs, func(a, b) {
                    if (a.timestamp > b.timestamp) { #less }
                    else if (a.timestamp < b.timestamp) { #greater }
                    else { #equal }
                });
                
                let size = Array.size(sorted);
                let takeCount = if (limit > size) { size } else { limit };
                Array.tabulate<Types.Notification>(takeCount, func(i) { sorted[i] })
            };
        }
    };
    
    // Get unread notification count
    public query func getUnreadCount(user: Principal) : async Nat {
        switch (notifications.get(user)) {
            case null { 0 };
            case (?notifs) {
                Array.foldLeft<Types.Notification, Nat>(notifs, 0, func(acc, n) {
                    if (not n.read) { acc + 1 } else { acc }
                })
            };
        }
    };
    
    // Mark notification as read
    public shared(msg) func markNotificationRead(notifId: Nat) : async Bool {
        let caller = msg.caller;
        
        switch (notifications.get(caller)) {
            case null { false };
            case (?notifs) {
                let updated = Array.map<Types.Notification, Types.Notification>(notifs, func(n) {
                    if (n.id == notifId) {
                        { n with read = true }
                    } else { n }
                });
                notifications.put(caller, updated);
                true
            };
        }
    };
    
    // Mark all notifications as read
    public shared(msg) func markAllNotificationsRead() : async () {
        let caller = msg.caller;
        
        switch (notifications.get(caller)) {
            case null {};
            case (?notifs) {
                let updated = Array.map<Types.Notification, Types.Notification>(notifs, func(n) {
                    { n with read = true }
                });
                notifications.put(caller, updated);
            };
        }
    };
    
    // Clear old notifications
    public shared(msg) func clearOldNotifications(olderThanDays: Nat) : async () {
        let caller = msg.caller;
        let cutoffTime = Time.now() - (olderThanDays * 24 * 60 * 60 * 1_000_000_000);
        
        switch (notifications.get(caller)) {
            case null {};
            case (?notifs) {
                let filtered = Array.filter<Types.Notification>(notifs, func(n) {
                    n.timestamp > cutoffTime
                });
                notifications.put(caller, filtered);
            };
        }
    };
    
    // ============= ACHIEVEMENTS =============
    
    // Award achievement
    private func awardAchievement(user: Principal, name: Text, description: Text, icon: Text) : async () {
        let achievementId = nextAchievementId;
        nextAchievementId += 1;
        
        let achievement : Types.Achievement = {
            id = achievementId;
            name = name;
            description = description;
            icon = icon;
            unlockedAt = Time.now();
        };
        
        let existing = switch (achievements.get(user)) {
            case null { [] };
            case (?a) { a };
        };
        
        // Check if already awarded
        let alreadyHas = Array.find<Types.Achievement>(existing, func(a) {
            a.name == name
        });
        
        if (Option.isNull(alreadyHas)) {
            achievements.put(user, Array.append(existing, [achievement]));
            
            // Create notification
            let _ = await createNotification(
                user,
                #SystemAlert,
                "🏆 Achievement Unlocked: " # name,
                null
            );
        };
    };
    
    // Check and award achievements based on user stats
    private func checkAndAwardAchievements(user: Principal, profile: Types.UserProfile) : async () {
        // First Goal
        if (profile.totalSaved > 0) {
            await awardAchievement(user, "First Step", "Created your first savings goal", "🎯");
        };
        
        // 0.1 BTC saved
        if (profile.totalSaved >= 10_000_000) {
            await awardAchievement(user, "Decimal Master", "Saved 0.1 BTC", "💎");
        };
        
        // 1 BTC saved
        if (profile.totalSaved >= 100_000_000) {
            await awardAchievement(user, "Whole Coiner", "Saved 1 full BTC", "🪙");
        };
        
        // Interest earned
        if (profile.totalInterestEarned > 0) {
            await awardAchievement(user, "Passive Income", "Earned your first interest", "📈");
        };
        
        // Tier achievements
        switch (profile.tier) {
            case (#Silver) {
                await awardAchievement(user, "Silver Saver", "Reached Silver tier", "🥈");
            };
            case (#Gold) {
                await awardAchievement(user, "Gold Standard", "Reached Gold tier", "🥇");
            };
            case (#Platinum) {
                await awardAchievement(user, "Platinum Legend", "Reached Platinum tier", "💠");
            };
            case _ {};
        };
    };
    
    // Get user achievements
    public query func getAchievements(user: Principal) : async [Types.Achievement] {
        switch (achievements.get(user)) {
            case null { [] };
            case (?a) { a };
        }
    };
    
    // ============= SOCIAL CONNECTIONS =============
    
    // Add friend
    public shared(msg) func addConnection(friendPrincipal: Principal) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        if (caller == friendPrincipal) {
            return #err("Cannot add yourself as a connection");
        };
        
        // Check if friend exists
        switch (users.get(friendPrincipal)) {
            case null { return #err("User not found") };
            case (?_) {};
        };
        
        let existing = switch (socialConnections.get(caller)) {
            case null { [] };
            case (?c) { c };
        };
        
        // Check if already connected
        let alreadyConnected = Array.find<Types.SocialConnection>(existing, func(c) {
            c.user == friendPrincipal
        });
        
        if (Option.isSome(alreadyConnected)) {
            return #err("Already connected");
        };
        
        let connection : Types.SocialConnection = {
            user = friendPrincipal;
            connectedAt = Time.now();
            sharedGoals = [];
        };
        
        socialConnections.put(caller, Array.append(existing, [connection]));
        #ok()
    };
    
    // Remove connection
    public shared(msg) func removeConnection(friendPrincipal: Principal) : async () {
        let caller = msg.caller;
        
        switch (socialConnections.get(caller)) {
            case null {};
            case (?connections) {
                let filtered = Array.filter<Types.SocialConnection>(connections, func(c) {
                    c.user != friendPrincipal
                });
                socialConnections.put(caller, filtered);
            };
        };
    };
    
    // Get user connections
    public query func getConnections(user: Principal) : async [Types.SocialConnection] {
        switch (socialConnections.get(user)) {
            case null { [] };
            case (?c) { c };
        }
    };
    
    // ============= STATISTICS =============
    
    // Get total user count
    public query func getTotalUsers() : async Nat {
        Iter.size(users.entries())
    };
    
    // Get active users (active in last 30 days)
    public query func getActiveUsers() : async Nat {
        let cutoff = Time.now() - (30 * 24 * 60 * 60 * 1_000_000_000);
        var count = 0;
        
        for ((_, profile) in users.entries()) {
            if (profile.lastActive > cutoff) {
                count += 1;
            };
        };
        
        count
    };
    
    // Get users by tier
    public query func getUsersByTier() : async [(Types.UserTier, Nat)] {
        var basic = 0;
        var silver = 0;
        var gold = 0;
        var platinum = 0;
        
        for ((_, profile) in users.entries()) {
            switch (profile.tier) {
                case (#Basic) { basic += 1 };
                case (#Silver) { silver += 1 };
                case (#Gold) { gold += 1 };
                case (#Platinum) { platinum += 1 };
            };
        };
        
        [
            (#Basic, basic),
            (#Silver, silver),
            (#Gold, gold),
            (#Platinum, platinum)
        ]
    };
}