#pragma version 0.4.0
# Voting contract with owner-controlled proposals, whitelist, 7-day voting cooldown, and ownership transfer

# Proposal structure
struct Proposal:
    description: String[256]  # Proposal text (up to 256 chars)
    votes: uint256[10]  # Votes for each option (index 0 = option 1, ..., 9 = option 10)
    active: bool  # Is voting active?

# State variables
proposals: public(HashMap[uint256, Proposal])  # Proposal ID -> Proposal
proposalCount: public(uint256)  # Total number of proposals
activeProposalId: public(uint256)  # ID of the currently active proposal (0 if none)
whitelist: public(HashMap[address, bool])  # Whitelisted voters
lastVoteTime: public(HashMap[address, uint256])  # Last vote timestamp per voter
owner: public(address)  # Contract owner
SEVEN_DAYS: constant(uint256) = 604800  # 7 days in seconds (7 * 24 * 60 * 60)
MAX_OPTIONS: constant(uint256) = 10  # Number of voting options (1-10)

# Events for logging
event ProposalSubmitted:
    id: uint256
    description: String[256]

event VotingStarted:
    id: uint256

event VotingStopped:
    id: uint256

event VoterAdded:
    voter: address

event VotersAdded:
    count: uint256

event WhitelistReset:
    resetBy: address

event Voted:
    voter: address
    proposalId: uint256
    choice: uint256  # Option chosen (1-10)
    timestamp: uint256

event OwnershipTransferred:
    previousOwner: address
    newOwner: address

# Initialize contract
@deploy
def __init__():
    self.owner = msg.sender
    self.proposalCount = 0
    self.activeProposalId = 0  # No active proposal at start

# Submit a new proposal (only owner)
@external
def submitProposal(description: String[256]):
    assert msg.sender == self.owner, "Only owner can submit proposals"
    assert len(description) > 0, "Description cannot be empty"
    proposalId: uint256 = self.proposalCount
    self.proposals[proposalId] = Proposal({
        description: description,
        votes: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  # Initialize votes for 10 options to 0
        active: False  # Inactive until started
    })
    self.proposalCount += 1
    log ProposalSubmitted(proposalId, description)

# Start voting on a proposal (only owner)
@external
def startVoting(proposalId: uint256):
    assert msg.sender == self.owner, "Only owner can start voting"
    assert proposalId < self.proposalCount, "Invalid proposal ID"
    assert not self.proposals[proposalId].active, "Voting already active"
    if self.activeProposalId != 0 or self.proposalCount == 1:  # Deactivate current if any
        self.proposals[self.activeProposalId].active = False
    self.proposals[proposalId].active = True
    self.activeProposalId = proposalId
    log VotingStarted(proposalId)

# Stop voting on the active proposal (only owner)
@external
def stopVoting():
    assert msg.sender == self.owner, "Only owner can stop voting"
    assert self.activeProposalId != 0 or self.proposalCount > 0, "No active proposal"
    self.proposals[self.activeProposalId].active = False
    log VotingStopped(self.activeProposalId)
    self.activeProposalId = 0  # Reset active ID

# Add a single voter to whitelist (only owner)
@external
def addVoter(voter: address):
    assert msg.sender == self.owner, "Only owner can add voters"
    assert voter != empty(address), "Invalid address"
    assert not self.whitelist[voter], "Voter already whitelisted"
    self.whitelist[voter] = True
    log VoterAdded(voter)

# Add multiple voters to whitelist (up to 30, only owner)
@external
def addVoters(voters: address[30]):
    assert msg.sender == self.owner, "Only owner can add voters"
    count: uint256 = 0
    for i: uint256 in range(30):
        if voters[i] == empty(address):
            break  # Stop at first empty address
        assert not self.whitelist[voters[i]], "Voter already whitelisted"
        self.whitelist[voters[i]] = True
        count += 1
    log VotersAdded(count)

# Reset whitelist by removing specific addresses (only owner)
@external
def removeFromWhitelist(addressesToRemove: address[30]):
    assert msg.sender == self.owner, "Only owner can reset whitelist"
    for i: uint256 in range(30):
        if addressesToRemove[i] == empty(address):
            break  # Stop at first empty address
        if self.whitelist[addressesToRemove[i]]:  # Only update if they were whitelisted
            self.whitelist[addressesToRemove[i]] = False
    log WhitelistReset(msg.sender)

# Vote on the active proposal (whitelisted voters only, once every 7 days)
@external
def vote(choice: uint256):
    assert self.activeProposalId != 0 or self.proposalCount > 0, "No active proposal"
    assert self.proposals[self.activeProposalId].active, "Voting not active"
    assert self.whitelist[msg.sender], "Not whitelisted to vote"
    assert choice >= 1 and choice <= MAX_OPTIONS, "Choice must be between 1 and 10"
    
    # Check 7-day cooldown
    currentTime: uint256 = block.timestamp
    lastVote: uint256 = self.lastVoteTime[msg.sender]
    assert lastVote == 0 or currentTime >= lastVote + SEVEN_DAYS, "Can only vote once every 7 days"

    # Record vote for the chosen option (choice - 1 for 0-based index)
    self.proposals[self.activeProposalId].votes[choice - 1] += 1
    self.lastVoteTime[msg.sender] = currentTime
    log Voted(msg.sender, self.activeProposalId, choice, currentTime)

# Change contract owner (only current owner)
@external
def changeOwner(newOwner: address):
    assert msg.sender == self.owner, "Only owner can change ownership"
    assert newOwner != empty(address), "New owner cannot be zero address"
    assert newOwner != self.owner, "New owner must be different"
    previousOwner: address = self.owner
    self.owner = newOwner
    log OwnershipTransferred(previousOwner, newOwner)

# Get active proposal details
@view
@external
def getActiveProposal() -> (String[256], uint256[10], bool):
    assert self.activeProposalId != 0 or self.proposalCount > 0, "No active proposal"
    p: Proposal = self.proposals[self.activeProposalId]
    return (p.description, p.votes, p.active)

# Get last vote time for a voter
@view
@external
def getLastVoteTime(voter: address) -> uint256:
    return self.lastVoteTime[voter]

# Check the winning option for a proposal
@view
@external
def checkWinnerForProposal(proposalId: uint256) -> (uint256, uint256):
    assert proposalId < self.proposalCount, "Invalid proposal ID"
    p: Proposal = self.proposals[proposalId]
    
    winningOption: uint256 = 0  # Default to option 1 (index 0)
    highestVotes: uint256 = 0
    
    for i: uint256 in range(MAX_OPTIONS):
        if p.votes[i] > highestVotes:
            highestVotes = p.votes[i]
            winningOption = i + 1  # Add 1 to convert to 1-based option number
    
    return (winningOption, highestVotes)  # Returns (winning option 1-10, vote count)