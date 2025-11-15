// Governance.mo - DAO Governance Canister for Protocol Decisions

import Types "./Types";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Option "mo:base/Option";

actor Governance {
    
    // ============= STATE =============
    
    private stable var nextProposalId : Nat = 0;
    private stable var savingsCanisterPrincipal : Principal = Principal.fromText("aaaaa-aa");
    private stable var governanceTokenPrincipal : Principal = Principal.fromText("aaaaa-aa");
    
    private stable var votingPeriodDays : Nat = 7;
    private stable var quorumPercentage : Nat = 2000; // 20% in basis points
    private stable var approvalThreshold : Nat = 5000; // 50% in basis points
    
    private var proposals = HashMap.HashMap<Nat, Types.Proposal>(100, Nat.equal, Nat.hash);
    private var votes = HashMap.HashMap<Nat, [Types.Vote]>(100, Nat.equal, Nat.hash);
    private var userVotes = HashMap.HashMap<Principal, [Nat]>(100, Principal.equal, Principal.hash);
    
    private stable var proposalsEntries : [(Nat, Types.Proposal)] = [];
    private stable var votesEntries : [(Nat, [Types.Vote])] = [];
    private stable var userVotesEntries : [(Principal, [Nat])] = [];
    
    system func preupgrade() {
        proposalsEntries := Iter.toArray(proposals.entries());
        votesEntries := Iter.toArray(votes.entries());
        userVotesEntries := Iter.toArray(userVotes.entries());
    };
    
    system func postupgrade() {
        proposals := HashMap.fromIter<Nat, Types.Proposal>(proposalsEntries.vals(), 100, Nat.equal, Nat.hash);
        votes := HashMap.fromIter<Nat, [Types.Vote]>(votesEntries.vals(), 100, Nat.equal, Nat.hash);
        userVotes := HashMap.fromIter<Principal, [Nat]>(userVotesEntries.vals(), 100, Principal.equal, Principal.hash);
        
        proposalsEntries := [];
        votesEntries := [];
        userVotesEntries := [];
    };
    
    // ============= CONSTANTS =============
    
    private let NANOSECONDS_PER_DAY : Int = 24 * 60 * 60 * 1_000_000_000;
    private let BASIS_POINTS : Nat = 10_000;
    private let MIN_VOTING_POWER : Nat = 100_000; // Minimum tokens to create proposal
    
    // ============= SETUP =============
    
    public shared(msg) func setSavingsCanister(canister: Principal) : async () {
        savingsCanisterPrincipal := canister;
    };
    
    public shared(msg) func setGovernanceToken(token: Principal) : async () {
        governanceTokenPrincipal := token;
    };
    
    public shared(msg) func updateVotingParameters(
        periodDays: ?Nat,
        quorum: ?Nat,
        threshold: ?Nat
    ) : async Result.Result<(), Text> {
        // In production, this should require a governance vote
        
        switch (periodDays) {
            case (?days) {
                if (days < 1 or days > 30) {
                    return #err("Voting period must be between 1 and 30 days");
                };
                votingPeriodDays := days;
            };
            case null {};
        };
        
        switch (quorum) {
            case (?q) {
                if (q > BASIS_POINTS) {
                    return #err("Quorum cannot exceed 100%");
                };
                quorumPercentage := q;
            };
            case null {};
        };
        
        switch (threshold) {
            case (?t) {
                if (t > BASIS_POINTS) {
                    return #err("Threshold cannot exceed 100%");
                };
                approvalThreshold := t;
            };
            case null {};
        };
        
        #ok()
    };
    
    // ============= PROPOSAL CREATION =============
    
    public shared(msg) func createProposal(
        title: Text,
        description: Text,
        proposalType: Types.ProposalType
    ) : async Result.Result<Nat, Text> {
        let caller = msg.caller;
        
        // Validate
        if (title.size() == 0 or title.size() > 200) {
            return #err("Title must be between 1 and 200 characters");
        };
        
        if (description.size() == 0 or description.size() > 5000) {
            return #err("Description must be between 1 and 5000 characters");
        };
        
        // Check voting power (simplified - in production, check token balance)
        let votingPower = await getVotingPower(caller);
        if (votingPower < MIN_VOTING_POWER) {
            return #err("Insufficient voting power to create proposal");
        };
        
        let proposalId = nextProposalId;
        nextProposalId += 1;
        
        let now = Time.now();
        let votingEnds = now + (Int.abs(votingPeriodDays) * NANOSECONDS_PER_DAY);
        
        let proposal : Types.Proposal = {
            id = proposalId;
            proposer = caller;
            title = title;
            description = description;
            proposalType = proposalType;
            createdAt = now;
            votingEndsAt = votingEnds;
            status = #Active;
            votesFor = 0;
            votesAgainst = 0;
            executed = false;
        };
        
        proposals.put(proposalId, proposal);
        votes.put(proposalId, []);
        
        #ok(proposalId)
    };
    
    // ============= VOTING =============
    
    public shared(msg) func vote(proposalId: Nat, support: Bool) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        // Get proposal
        let proposal = switch (proposals.get(proposalId)) {
            case null { return #err("Proposal not found") };
            case (?p) { p };
        };
        
        // Check if voting is still open
        if (proposal.status != #Active) {
            return #err("Voting is closed for this proposal");
        };
        
        let now = Time.now();
        if (now > proposal.votingEndsAt) {
            return #err("Voting period has ended");
        };
        
        // Check if already voted
        let proposalVotes = switch (votes.get(proposalId)) {
            case null { [] };
            case (?v) { v };
        };
        
        let alreadyVoted = Array.find<Types.Vote>(proposalVotes, func(v) {
            v.voter == caller
        });
        
        if (Option.isSome(alreadyVoted)) {
            return #err("Already voted on this proposal");
        };
        
        // Get voting power
        let votingPower = await getVotingPower(caller);
        if (votingPower == 0) {
            return #err("No voting power");
        };
        
        // Create vote
        let newVote : Types.Vote = {
            proposalId = proposalId;
            voter = caller;
            vote = support;
            votingPower = votingPower;
            timestamp = now;
        };
        
        // Update votes
        votes.put(proposalId, Array.append(proposalVotes, [newVote]));
        
        // Update user votes
        let userProposals = switch (userVotes.get(caller)) {
            case null { [] };
            case (?p) { p };
        };
        userVotes.put(caller, Array.append(userProposals, [proposalId]));
        
        // Update proposal vote counts
        let updatedProposal = if (support) {
            { proposal with votesFor = proposal.votesFor + votingPower }
        } else {
            { proposal with votesAgainst = proposal.votesAgainst + votingPower }
        };
        proposals.put(proposalId, updatedProposal);
        
        #ok()
    };
    
    // ============= PROPOSAL EXECUTION =============
    
    public shared(msg) func finalizeProposal(proposalId: Nat) : async Result.Result<(), Text> {
        let proposal = switch (proposals.get(proposalId)) {
            case null { return #err("Proposal not found") };
            case (?p) { p };
        };
        
        if (proposal.status != #Active) {
            return #err("Proposal is not active");
        };
        
        let now = Time.now();
        if (now <= proposal.votingEndsAt) {
            return #err("Voting period has not ended yet");
        };
        
        // Calculate results
        let totalVotes = proposal.votesFor + proposal.votesAgainst;
        let totalSupply = await getTotalVotingPower();
        
        // Check quorum
        let quorumReached = (totalVotes * BASIS_POINTS) >= (totalSupply * quorumPercentage);
        
        if (not quorumReached) {
            let rejectedProposal = {
                proposal with
                status = #Rejected;
            };
            proposals.put(proposalId, rejectedProposal);
            return #err("Quorum not reached");
        };
        
        // Check if passed
        let approvalRate = if (totalVotes > 0) {
            (proposal.votesFor * BASIS_POINTS) / totalVotes
        } else { 0 };
        
        let passed = approvalRate >= approvalThreshold;
        
        let newStatus = if (passed) { #Passed } else { #Rejected };
        let updatedProposal = {
            proposal with
            status = newStatus;
        };
        proposals.put(proposalId, updatedProposal);
        
        if (passed) {
            #ok()
        } else {
            #err("Proposal rejected")
        }
    };
    
    public shared(msg) func executeProposal(proposalId: Nat) : async Result.Result<(), Text> {
        // Only admin or executor can execute
        
        let proposal = switch (proposals.get(proposalId)) {
            case null { return #err("Proposal not found") };
            case (?p) { p };
        };
        
        if (proposal.status != #Passed) {
            return #err("Proposal has not passed");
        };
        
        if (proposal.executed) {
            return #err("Proposal already executed");
        };
        
        // Execute based on proposal type
        switch (proposal.proposalType) {
            case (#ChangeInterestRate(newRate)) {
                // Call savings canister to update interest rate
                // This is a simplified example
                let updatedProposal = { proposal with executed = true };
                proposals.put(proposalId, updatedProposal);
                #ok()
            };
            case (#ChangePenaltyRate(newRate)) {
                // Call savings canister to update penalty rate
                let updatedProposal = { proposal with executed = true };
                proposals.put(proposalId, updatedProposal);
                #ok()
            };
            case (#AddFeature(feature)) {
                // Mark as executed (manual implementation needed)
                let updatedProposal = { proposal with executed = true };
                proposals.put(proposalId, updatedProposal);
                #ok()
            };
            case (#UpdateProtocol(update)) {
                // Mark as executed (manual implementation needed)
                let updatedProposal = { proposal with executed = true };
                proposals.put(proposalId, updatedProposal);
                #ok()
            };
        }
    };
    
    // ============= QUERIES =============
    
    public query func getProposal(proposalId: Nat) : async ?Types.Proposal {
        proposals.get(proposalId)
    };
    
    public query func getAllProposals(status: ?Types.ProposalStatus, limit: Nat, offset: Nat) : async [Types.Proposal] {
        let buffer = Buffer.Buffer<Types.Proposal>(limit);
        var count = 0;
        var skipped = 0;
        
        for ((_, proposal) in proposals.entries()) {
            if (count >= limit) { return Buffer.toArray(buffer) };
            
            let matches = switch (status) {
                case null { true };
                case (?s) { proposal.status == s };
            };
            
            if (matches) {
                if (skipped >= offset) {
                    buffer.add(proposal);
                    count += 1;
                } else {
                    skipped += 1;
                };
            };
        };
        
        // Sort by creation date (newest first)
        let sorted = Array.sort<Types.Proposal>(Buffer.toArray(buffer), func(a, b) {
            if (a.createdAt > b.createdAt) { #less }
            else if (a.createdAt < b.createdAt) { #greater }
            else { #equal }
        });
        
        sorted
    };
    
    public query func getActiveProposals() : async [Types.Proposal] {
        let buffer = Buffer.Buffer<Types.Proposal>(10);
        let now = Time.now();
        
        for ((_, proposal) in proposals.entries()) {
            if (proposal.status == #Active and now <= proposal.votingEndsAt) {
                buffer.add(proposal);
            };
        };
        
        Buffer.toArray(buffer)
    };
    
    public query func getProposalVotes(proposalId: Nat) : async [Types.Vote] {
        switch (votes.get(proposalId)) {
            case null { [] };
            case (?v) { v };
        }
    };
    
    public query func getUserVotes(user: Principal) : async [Nat] {
        switch (userVotes.get(user)) {
            case null { [] };
            case (?v) { v };
        }
    };
    
    public query func getProposalStats(proposalId: Nat) : async ?{
        totalVotes: Nat;
        votesFor: Nat;
        votesAgainst: Nat;
        participationRate: Nat; // in basis points
        approvalRate: Nat; // in basis points
        quorumReached: Bool;
        timeRemaining: Int;
    } {
        let proposal = switch (proposals.get(proposalId)) {
            case null { return null };
            case (?p) { p };
        };
        
        let totalVotes = proposal.votesFor + proposal.votesAgainst;
        let totalSupply = await getTotalVotingPower();
        
        let participationRate = if (totalSupply > 0) {
            (totalVotes * BASIS_POINTS) / totalSupply
        } else { 0 };
        
        let approvalRate = if (totalVotes > 0) {
            (proposal.votesFor * BASIS_POINTS) / totalVotes
        } else { 0 };
        
        let quorumReached = participationRate >= quorumPercentage;
        
        let now = Time.now();
        let timeRemaining = proposal.votingEndsAt - now;
        
        ?{
            totalVotes = totalVotes;
            votesFor = proposal.votesFor;
            votesAgainst = proposal.votesAgainst;
            participationRate = participationRate;
            approvalRate = approvalRate;
            quorumReached = quorumReached;
            timeRemaining = timeRemaining;
        }
    };
    
    public query func getGovernanceParams() : async {
        votingPeriodDays: Nat;
        quorumPercentage: Nat;
        approvalThreshold: Nat;
        minVotingPower: Nat;
    } {
        {
            votingPeriodDays = votingPeriodDays;
            quorumPercentage = quorumPercentage;
            approvalThreshold = approvalThreshold;
            minVotingPower = MIN_VOTING_POWER;
        }
    };
    
    // ============= HELPER FUNCTIONS =============
    
    private func getVotingPower(user: Principal) : async Nat {
        // In production, this would query the governance token balance
        // For now, return a simplified calculation based on TVL in savings
        
        // This is a placeholder - integrate with actual token/savings data
        100_000 // Default voting power
    };
    
    private func getTotalVotingPower() : async Nat {
        // Total voting power of all token holders
        // Placeholder implementation
        1_000_000
    };
    
    // ============= DELEGATION (FUTURE) =============
    
    // Users could delegate their voting power to others
    public shared(msg) func delegateVotingPower(delegate: Principal) : async Result.Result<(), Text> {
        let caller = msg.caller;
        
        if (caller == delegate) {
            return #err("Cannot delegate to yourself");
        };
        
        // Implementation would track delegations
        #ok()
    };
    
    public shared(msg) func revokeDelegation() : async Result.Result<(), Text> {
        // Implementation would remove delegation
        #ok()
    };
}