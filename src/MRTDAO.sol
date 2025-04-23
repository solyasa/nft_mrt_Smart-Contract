// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMRTCollection {
    enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
    function tokenRarity(uint256 tokenId) external view returns (Rarity);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function reduceMaxSupply(uint256 reductionAmount) external returns (bool);
    function getAvailableSupply() external view returns (uint256);
}

interface IMRTStaking {
    function getUserStakedTokens(address user) external view returns (uint256[] memory);
    function getStakingInfo(uint256 tokenId) external view returns (
        uint256 stakedTimestamp,
        uint256 lastClaimTimestamp,
        address owner,
        bool isStaked
    );
}

/**
 * @title MRTDAO
 * @dev DAO governance contract for MRT ecosystem
 */
contract MRTDAO is Ownable, ReentrancyGuard {  
    // NFT Collection contract
    IMRTCollection public nftCollection;
    
    // MRT token
    IERC20 public mrtToken;
    
    // Staking contract
    IMRTStaking public stakingContract;
    
    // Proposal struct
    struct Proposal {
        uint256 id;
        string title;
        string description;
        uint256 startTime;
        uint256 endTime;
        address proposer;
        bool executed;
        bytes callData;
        address targetContract;
        uint256 forVotes;
        uint256 againstVotes;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) votingPower;
        mapping(address => bool) voteDirection; // true = for, false = against
    }
    
    // Proposal types
    enum ProposalType { STANDARD, ONCHAIN }
    
    // Extended proposal data
    struct ProposalData {
        ProposalType proposalType;
    }
    
    // Proposal mapping and counter
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => ProposalData) public proposalData;
    uint256 public proposalCount;
    
    // Voting parameters
    uint256 public votingPeriod = 7 days;
    uint256 public executionDelay = 2 days;
    uint256 public minProposalThreshold = 100 * 10**18; // 100 MRT tokens
    
    // Voting power multipliers for NFTs based on rarity
    mapping(IMRTCollection.Rarity => uint256) public nftVotingPowerMultiplier;
    
    // Community fund
    uint256 public communityFund;
    
    // Events
    event ProposalCreated(uint256 indexed proposalId, string title, address proposer, ProposalType proposalType);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 votingPower);
    event ProposalExecuted(uint256 indexed proposalId);
    event FundsAdded(uint256 amount);
    event FundsWithdrawn(address recipient, uint256 amount);
    event VotingParametersUpdated(uint256 votingPeriod, uint256 executionDelay, uint256 minProposalThreshold);
    event NFTVotingPowerUpdated(uint256[] votingPowerMultipliers);
    event MaxSupplyReduced(uint256 reductionAmount);
    event StakingContractUpdated(address stakingContract);
    
    /**
     * @dev Constructor
     * @param nftCollectionAddress The address of the NFT collection contract
     * @param mrtTokenAddress The address of the MRT token contract
     * @param stakingContractAddress The address of the staking contract
     */
    constructor(
        address nftCollectionAddress,
        address mrtTokenAddress,
        address stakingContractAddress
    ) Ownable(msg.sender) {
        nftCollection = IMRTCollection(nftCollectionAddress);
        mrtToken = IERC20(mrtTokenAddress);
        stakingContract = IMRTStaking(stakingContractAddress);
        
        // Set initial voting power multipliers for NFTs based on rarity
        nftVotingPowerMultiplier[IMRTCollection.Rarity.COMMON] = 10000; // 1.0x (10000 = 100%)
        nftVotingPowerMultiplier[IMRTCollection.Rarity.UNCOMMON] = 20000; // 2.0x
        nftVotingPowerMultiplier[IMRTCollection.Rarity.RARE] = 50000; // 5.0x
        nftVotingPowerMultiplier[IMRTCollection.Rarity.EPIC] = 100000; // 10.0x
        nftVotingPowerMultiplier[IMRTCollection.Rarity.LEGENDARY] = 250000; // 25.0x
    }
    
    /**
     * @dev Update staking contract address
     * @param _stakingContractAddress New staking contract address
     */
    function updateStakingContract(address _stakingContractAddress) external onlyOwner {
        stakingContract = IMRTStaking(_stakingContractAddress);
        emit StakingContractUpdated(_stakingContractAddress);
    }
    
    /**
     * @dev Update voting parameters
     * @param _votingPeriod New voting period in seconds
     * @param _executionDelay New execution delay in seconds
     * @param _minProposalThreshold New minimum proposal threshold
     */
    function updateVotingParameters(
        uint256 _votingPeriod,
        uint256 _executionDelay,
        uint256 _minProposalThreshold
    ) external onlyOwner {
        votingPeriod = _votingPeriod;
        executionDelay = _executionDelay;
        minProposalThreshold = _minProposalThreshold;
        
        emit VotingParametersUpdated(_votingPeriod, _executionDelay, _minProposalThreshold);
    }
    
    /**
     * @dev Update NFT voting power multipliers
     * @param votingPowerMultipliers Array of voting power multipliers [COMMON, UNCOMMON, RARE, EPIC, LEGENDARY]
     */
    function updateNFTVotingPower(uint256[] calldata votingPowerMultipliers) external onlyOwner {
        require(votingPowerMultipliers.length == 5, "Invalid array length");
        
        nftVotingPowerMultiplier[IMRTCollection.Rarity.COMMON] = votingPowerMultipliers[0];
        nftVotingPowerMultiplier[IMRTCollection.Rarity.UNCOMMON] = votingPowerMultipliers[1];
        nftVotingPowerMultiplier[IMRTCollection.Rarity.RARE] = votingPowerMultipliers[2];
        nftVotingPowerMultiplier[IMRTCollection.Rarity.EPIC] = votingPowerMultipliers[3];
        nftVotingPowerMultiplier[IMRTCollection.Rarity.LEGENDARY] = votingPowerMultipliers[4];
        
        emit NFTVotingPowerUpdated(votingPowerMultipliers);
    }
    
    /**
     * @dev Add funds to community treasury
     */
    function addFunds() external payable {
        communityFund = communityFund + msg.value;
        emit FundsAdded(msg.value);
    }
    
    /**
     * @dev Add ERC20 tokens to community treasury
     * @param amount Amount of MRT tokens to add
     */
    function addTokenFunds(uint256 amount) external {
        require(mrtToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        emit FundsAdded(amount);
    }
    
    /**
     * @dev Calculate the voting power of an address
     * @param voter The address to calculate voting power for
     * @return The total voting power
     */
    function calculateVotingPower(address voter) public view returns (uint256) {
        // Get token balance
        uint256 tokenBalance = mrtToken.balanceOf(voter) / 10**18; // Convert to whole tokens
        
        // Return 0 if no tokens
        if (tokenBalance == 0) {
            return 0;
        }
        
        // Calculate NFT multiplier from NFTs in wallet
        uint256 totalMultiplier = 10000; // Base multiplier of 1.0x (100%)
        
        // Add multiplier from wallet NFTs
        uint256 nftCount = nftCollection.balanceOf(voter);
        for (uint256 i = 0; i < nftCount; i++) {
            uint256 tokenId = nftCollection.tokenOfOwnerByIndex(voter, i);
            IMRTCollection.Rarity rarity = nftCollection.tokenRarity(tokenId);
            totalMultiplier += nftVotingPowerMultiplier[rarity]; // Add the bonus part of the multiplier
        }
        
        // Add multiplier from staked NFTs
        uint256[] memory stakedTokens = stakingContract.getUserStakedTokens(voter);
        for (uint256 i = 0; i < stakedTokens.length; i++) {
            uint256 tokenId = stakedTokens[i];
            
            // Verify the token is still staked and owned by the voter
            (,, address owner, bool isStaked) = stakingContract.getStakingInfo(tokenId);
            
            if (isStaked && owner == voter) {
                IMRTCollection.Rarity rarity = nftCollection.tokenRarity(tokenId);
                totalMultiplier += nftVotingPowerMultiplier[rarity]; // Add the bonus part of the multiplier
            }
        }
        
        // Apply multiplier to token balance
        return (tokenBalance * totalMultiplier) / 10000;
    }
    
    /**
     * @dev Create a new proposal (standard or on-chain)
     * @param title Proposal title
     * @param description Proposal description
     * @param proposalType Type of proposal (STANDARD or ONCHAIN)
     * @param targetContract Contract to call if proposal passes (only for ONCHAIN proposals)
     * @param callData Function call data for execution (only for ONCHAIN proposals)
     */
    function createProposal(
        string memory title,
        string memory description,
        ProposalType proposalType,
        address targetContract,
        bytes memory callData
    ) external nonReentrant {
        uint256 votingPower = calculateVotingPower(msg.sender);
        require(votingPower >= minProposalThreshold, "Insufficient voting power to create proposal");
        
        // For on-chain proposals, require callData and targetContract
        if (proposalType == ProposalType.ONCHAIN) {
            require(targetContract != address(0), "Target contract cannot be zero address");
            require(callData.length > 0, "Call data cannot be empty for on-chain proposals");
        }
        
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.proposer = msg.sender;
        proposal.executed = false;
        
        // Only set callData and targetContract for on-chain proposals
        if (proposalType == ProposalType.ONCHAIN) {
            proposal.callData = callData;
            proposal.targetContract = targetContract;
        }
        
        // Set proposal type
        proposalData[proposalId].proposalType = proposalType;
        
        emit ProposalCreated(proposalId, title, msg.sender, proposalType);
    }
    
    /**
     * @dev Cast vote on a proposal
     * @param proposalId The ID of the proposal
     * @param support Whether to vote for or against the proposal
     */
    function castVote(uint256 proposalId, bool support) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(block.timestamp >= proposal.startTime, "Voting has not started");
        require(block.timestamp <= proposal.endTime, "Voting has ended");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 votingPower = calculateVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");
        
        proposal.hasVoted[msg.sender] = true;
        proposal.votingPower[msg.sender] = votingPower;
        proposal.voteDirection[msg.sender] = support;
        
        if (support) {
            proposal.forVotes = proposal.forVotes + votingPower;
        } else {
            proposal.againstVotes = proposal.againstVotes + votingPower;
        }
        
        emit Voted(proposalId, msg.sender, support, votingPower);
    }
    
    /**
     * @dev Execute a successful proposal
     * @param proposalId The ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        ProposalData storage data = proposalData[proposalId];
        
        require(block.timestamp > proposal.endTime, "Voting still in progress");
        require(block.timestamp <= proposal.endTime + executionDelay, "Execution window passed");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.forVotes > proposal.againstVotes, "Proposal did not pass");
        
        proposal.executed = true;
        
        // For on-chain proposals, execute the call
        if (data.proposalType == ProposalType.ONCHAIN) {
            // Execute the proposal
            (bool success, ) = proposal.targetContract.call(proposal.callData);
            require(success, "Proposal execution failed");
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    /**
     * @dev Withdraw funds from community treasury (requires DAO proposal)
     * @param recipient Recipient of the funds
     * @param amount Amount to withdraw
     */
    function withdrawFunds(address payable recipient, uint256 amount) internal {
        require(amount <= communityFund, "Insufficient funds");
        
        communityFund = communityFund - amount;

        (bool success,) = recipient.call{value: amount}("");

        require(success, "Transfer failed");
        emit FundsWithdrawn(recipient, amount);
    }
    
    /**
     * @dev Withdraw ERC20 tokens from treasury (requires DAO proposal)
     * @param recipient Recipient of the tokens
     * @param amount Amount to withdraw
     */
    function withdrawTokens(address recipient, uint256 amount) internal {
        require(mrtToken.transfer(recipient, amount), "Token transfer failed");
        
        emit FundsWithdrawn(recipient, amount);
    }
    
    /**
     * @dev Reduce max supply of the NFT collection (requires DAO proposal)
     * @param reductionAmount Amount to reduce max supply by
     */
    function reduceMaxSupply(uint256 reductionAmount) internal returns (bool) {
        // Call the NFT collection contract to reduce max supply
        bool success = nftCollection.reduceMaxSupply(reductionAmount);
        require(success, "Max supply reduction failed");
        
        emit MaxSupplyReduced(reductionAmount);
        return true;
    }
    
    /**
     * @dev Get proposal details
     * @param proposalId The ID of the proposal
     */
    function getProposalDetails(uint256 proposalId) external view returns (
        string memory title,
        string memory description,
        uint256 startTime,
        uint256 endTime,
        address proposer,
        bool executed,
        uint256 forVotes,
        uint256 againstVotes,
        ProposalType proposalType
    ) {
        Proposal storage proposal = proposals[proposalId];
        ProposalData storage data = proposalData[proposalId];
        
        return (
            proposal.title,
            proposal.description,
            proposal.startTime,
            proposal.endTime,
            proposal.proposer,
            proposal.executed,
            proposal.forVotes,
            proposal.againstVotes,
            data.proposalType
        );
    }
    
    /**
     * @dev Check if an address has voted on a proposal
     * @param proposalId The ID of the proposal
     * @param voter The address to check
     * @return Whether the address has voted and their voting direction
     */
    function hasVoted(uint256 proposalId, address voter) external view returns (bool, bool) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.hasVoted[voter], proposal.voteDirection[voter]);
    }
    
    /**
     * @dev Receive function to accept ETH payments
     */
    receive() external payable {
        communityFund = communityFund + msg.value;
        emit FundsAdded(msg.value);
    }
}