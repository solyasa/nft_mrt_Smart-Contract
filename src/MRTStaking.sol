// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMRTCollection {
    enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
    function tokenRarity(uint256 tokenId) external view returns (Rarity);
}

/**
 * @title MRTStaking
 * @dev Staking contract for MRT NFTs
 */
contract MRTStaking is Ownable, ERC721Holder, ReentrancyGuard {
    
    // NFT Collection contract
    IERC721 public nftCollection;
    IMRTCollection public nftCollectionRarity;
    
    // MRT token
    IERC20 public mrtToken;
    
    // Staking functionality
    struct StakingInfo {
        uint256 stakedTimestamp;
        uint256 lastClaimTimestamp;
        address owner;
        bool isStaked;
    }
    mapping(uint256 => StakingInfo) public tokenStakingInfo;
    
    // Staking periods with multipliers
    struct StakingPeriod {
        uint256 days_;
        uint256 multiplier; // in basis points (100 = 1%)
    }
    StakingPeriod[] public stakingPeriods;
    
    // Reward rates per rarity (tokens per day)
    mapping(IMRTCollection.Rarity => uint256) public rewardRates;
    
    // User staking data
    mapping(address => uint256[]) public userStakedTokens;
    
    // Rewards pool
    uint256 public rewardsPool;
    
    // Events
    event StakingStarted(address indexed owner, uint256 indexed tokenId, uint256 timestamp);
    event StakingEnded(address indexed owner, uint256 indexed tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed owner, uint256 tokenId, uint256 amount);
    event RewardRatesUpdated(uint256[] rates);
    event StakingPeriodsUpdated();
    event RewardsAdded(uint256 amount);
    
    /**
     * @dev Constructor
     * @param nftCollectionAddress The address of the NFT collection contract
     * @param mrtTokenAddress The address of the MRT token contract
     */
    constructor(
        address nftCollectionAddress,
        address mrtTokenAddress
    ) Ownable(msg.sender) {
        nftCollection = IERC721(nftCollectionAddress);
        nftCollectionRarity = IMRTCollection(nftCollectionAddress);
        mrtToken = IERC20(mrtTokenAddress);
        
        // Set initial reward rates (tokens per day)
        rewardRates[IMRTCollection.Rarity.COMMON] = 10 * 10**18;     // 10 tokens/day
        rewardRates[IMRTCollection.Rarity.UNCOMMON] = 25 * 10**18;   // 25 tokens/day
        rewardRates[IMRTCollection.Rarity.RARE] = 50 * 10**18;       // 50 tokens/day
        rewardRates[IMRTCollection.Rarity.EPIC] = 100 * 10**18;      // 100 tokens/day
        rewardRates[IMRTCollection.Rarity.LEGENDARY] = 250 * 10**18; // 250 tokens/day
        
        // Set staking periods
        stakingPeriods.push(StakingPeriod(7, 10000));     // 7 days, 1x multiplier
        stakingPeriods.push(StakingPeriod(30, 11000));    // 30 days, 1.1x multiplier
        stakingPeriods.push(StakingPeriod(90, 12500));    // 90 days, 1.25x multiplier
        stakingPeriods.push(StakingPeriod(180, 15000));   // 180 days, 1.5x multiplier
    }
    
    /**
     * @dev Update reward rates for different rarities
     * @param rates Array of reward rates [COMMON, UNCOMMON, RARE, EPIC, LEGENDARY]
     */
    function updateRewardRates(uint256[] calldata rates) external onlyOwner {
        require(rates.length == 5, "Invalid rates array length");
        
        rewardRates[IMRTCollection.Rarity.COMMON] = rates[0];
        rewardRates[IMRTCollection.Rarity.UNCOMMON] = rates[1];
        rewardRates[IMRTCollection.Rarity.RARE] = rates[2];
        rewardRates[IMRTCollection.Rarity.EPIC] = rates[3];
        rewardRates[IMRTCollection.Rarity.LEGENDARY] = rates[4];
        
        emit RewardRatesUpdated(rates);
    }
    
    /**
     * @dev Update staking periods
     * @param days_ Array of staking periods in days
     * @param multipliers Array of multipliers in basis points (100 = 1%)
     */
    function updateStakingPeriods(
        uint256[] calldata days_,
        uint256[] calldata multipliers
    ) external onlyOwner {
        require(days_.length == multipliers.length, "Array lengths mismatch");
        
        delete stakingPeriods;
        
        for (uint256 i = 0; i < days_.length; i++) {
            stakingPeriods.push(StakingPeriod(days_[i], multipliers[i]));
        }
        
        emit StakingPeriodsUpdated();
    }
    
    /**
     * @dev Add rewards to the pool
     * @param amount Amount of MRT tokens to add
     */
    function addRewards(uint256 amount) external {
        require(mrtToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        rewardsPool = rewardsPool + amount;
        emit RewardsAdded(amount);
    }
    
    /**
     * @dev Calculate rewards for a staked token
     * @param tokenId The token ID
     * @param claimTimestamp The timestamp to calculate rewards up to
     * @return The calculated reward amount
     */
    function calculateRewards(uint256 tokenId, uint256 claimTimestamp) public view returns (uint256) {
        StakingInfo storage stakingInfo = tokenStakingInfo[tokenId];
        
        if (!stakingInfo.isStaked) {
            return 0;
        }
        
        uint256 lastClaimTime = stakingInfo.lastClaimTimestamp > 0 
            ? stakingInfo.lastClaimTimestamp 
            : stakingInfo.stakedTimestamp;
            
        uint256 stakingDuration = claimTimestamp - stakingInfo.stakedTimestamp;
        uint256 claimDuration = claimTimestamp - lastClaimTime;
        
        if (claimDuration == 0) {
            return 0;
        }
        
        // Get token rarity and base reward rate
        IMRTCollection.Rarity rarity = nftCollectionRarity.tokenRarity(tokenId);
        uint256 rewardRate = rewardRates[rarity];
        
        // Find applicable multiplier based on staking duration
        uint256 multiplier = 10000; // Default 1x multiplier
        for (uint256 i = 0; i < stakingPeriods.length; i++) {
            if (stakingDuration >= stakingPeriods[i].days_ * 1 days) {
                multiplier = stakingPeriods[i].multiplier;
            } else {
                break;
            }
        }
        
        // Calculate rewards: (daily reward * days * multiplier / 10000)
        uint256 daysStaked = claimDuration / 1 days;
        uint256 reward = rewardRate * daysStaked * multiplier / 10000;
        
        return reward;
    }
    
    /**
     * @dev Stake NFT
     * @param tokenId The token ID to stake
     */
    function stakeNFT(uint256 tokenId) external nonReentrant {
        require(nftCollection.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!tokenStakingInfo[tokenId].isStaked, "Token already staked");
        
        // Transfer NFT to staking contract
        nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        
        // Update staking info
        tokenStakingInfo[tokenId] = StakingInfo({
            stakedTimestamp: block.timestamp,
            lastClaimTimestamp: block.timestamp,
            owner: msg.sender,
            isStaked: true
        });
        
        // Add to user's staked tokens
        userStakedTokens[msg.sender].push(tokenId);
        
        emit StakingStarted(msg.sender, tokenId, block.timestamp);
    }
    
    /**
     * @dev Unstake NFT and claim rewards
     * @param tokenId The token ID to unstake
     */
    function unstakeNFT(uint256 tokenId) external nonReentrant {
        StakingInfo storage stakingInfo = tokenStakingInfo[tokenId];
        
        require(stakingInfo.isStaked, "Token not staked");
        require(stakingInfo.owner == msg.sender, "Not staking owner");
        
        // Calculate rewards
        uint256 reward = calculateRewards(tokenId, block.timestamp);
        
        // Update staking info
        stakingInfo.isStaked = false;
        
        // Remove from user's staked tokens
        uint256[] storage userTokens = userStakedTokens[msg.sender];
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == tokenId) {
                // Replace with the last element and pop
                userTokens[i] = userTokens[userTokens.length - 1];
                userTokens.pop();
                break;
            }
        }
        
        // Transfer NFT back to owner
        nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);
        
        // Transfer rewards if any
        if (reward > 0 && reward <= rewardsPool) {
            rewardsPool = rewardsPool - reward;
            require(mrtToken.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardsClaimed(msg.sender, tokenId, reward);
        }
        
        emit StakingEnded(msg.sender, tokenId, block.timestamp);
    }
    
    /**
     * @dev Claim rewards without unstaking
     * @param tokenId The token ID to claim rewards for
     */
    function claimRewards(uint256 tokenId) external nonReentrant {
        StakingInfo storage stakingInfo = tokenStakingInfo[tokenId];
        
        require(stakingInfo.isStaked, "Token not staked");
        require(stakingInfo.owner == msg.sender, "Not staking owner");
        
        // Calculate rewards
        uint256 reward = calculateRewards(tokenId, block.timestamp);
        require(reward > 0, "No rewards to claim");
        require(reward <= rewardsPool, "Insufficient rewards in pool");
        
        // Update last claim timestamp
        stakingInfo.lastClaimTimestamp = block.timestamp;
        
        // Transfer rewards
        rewardsPool = rewardsPool - reward;
        require(mrtToken.transfer(msg.sender, reward), "Reward transfer failed");
        
        emit RewardsClaimed(msg.sender, tokenId, reward);
    }
    
    /**
     * @dev Get all staked tokens for a user
     * @param user The user address
     * @return Array of token IDs staked by the user
     */
    function getUserStakedTokens(address user) external view returns (uint256[] memory) {
        return userStakedTokens[user];
    }
    
    /**
     * @dev Get staking info for a token
     * @param tokenId The token ID
     */
    function getStakingInfo(uint256 tokenId) external view returns (
        uint256 stakedTimestamp,
        uint256 lastClaimTimestamp,
        address owner,
        bool isStaked
    ) {
        StakingInfo storage info = tokenStakingInfo[tokenId];
        return (
            info.stakedTimestamp,
            info.lastClaimTimestamp,
            info.owner,
            info.isStaked
        );
    }
    
    /**
     * @dev Emergency withdraw in case of critical issues
     * @param tokenIds Array of token IDs to withdraw
     */
    function emergencyWithdraw(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            StakingInfo storage stakingInfo = tokenStakingInfo[tokenId];
            
            if (stakingInfo.isStaked) {
                address owner = stakingInfo.owner;
                stakingInfo.isStaked = false;
                
                nftCollection.safeTransferFrom(address(this), owner, tokenId);
                emit StakingEnded(owner, tokenId, block.timestamp);
            }
        }
    }
}