// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {MRTCollection} from "../src/MRTCollection.sol";
import {MRTStaking} from "../src/MRTStaking.sol";
import {MRTDAO} from "../src/MRTDAO.sol";
import {MRTPresale} from"../src/MRTPresale.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployMRTEcosystem is Script {
    // ERC20 Token address (this should be already deployed)
    address public mrtTokenAddress;
    
    // Configuration parameters
    string public constant NFT_NAME = "MRT Collection";
    string public constant NFT_SYMBOL = "MRT";
    string public constant BASE_URI = "https://mrt-api.example.com/metadata/";
    uint96 public constant ROYALTY_PERCENTAGE = 750; // 7.5%
    
    // Wallet addresses
    address public daoWallet;
    address public stakingWallet;
    address public communityWallet;
    address public devWallet;
    address public marketingWallet;
    address public teamWallet;
    address public trustedOracle;
    address public usdtTokenAddress;
    // Deployed contract addresses
    MRTCollection public mrtCollection;
    MRTStaking public mrtStaking;
    MRTDAO public mrtDao;
    MRTPresale public mrtPresale;
    
    function setUp() public {
        // Set the MRT token address (replace with actual address)
        mrtTokenAddress = address(0x1234567890123456789012345678901234567890); // Replace with actual token address
        
        // Set up wallet addresses (replace with actual addresses)
        trustedOracle = vm.addr(1);
        daoWallet = vm.addr(2);
        stakingWallet = vm.addr(3);
        communityWallet = vm.addr(4);
        devWallet = vm.addr(5);
        marketingWallet = vm.addr(6);
        teamWallet = vm.addr(7);
        
        // For testing purposes, you can use these instead:
        // trustedOracle = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        // daoWallet = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        // etc.
    }
    
    function run() public {
        setUp();
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        console.log("Starting MRT Ecosystem Deployment...");
        
        // 1. Deploy MRTCollection
        console.log("Deploying MRTCollection...");
        mrtCollection = new MRTCollection(
            NFT_NAME,
            NFT_SYMBOL,
            BASE_URI,
            mrtTokenAddress,
            trustedOracle,
            daoWallet, // DAO contract address (initially a wallet, will update later)
            ROYALTY_PERCENTAGE
        );
        console.log("MRTCollection deployed at:", address(mrtCollection));
        
        // 2. Deploy MRTStaking
        console.log("Deploying MRTStaking...");
        mrtStaking = new MRTStaking(
            address(mrtCollection),
            mrtTokenAddress
        );
        console.log("MRTStaking deployed at:", address(mrtStaking));
        
        // 3. Deploy MRTDAO
        console.log("Deploying MRTDAO...");
        mrtDao = new MRTDAO(
            address(mrtCollection),
            mrtTokenAddress,
            address(mrtStaking)
        );
        console.log("MRTDAO deployed at:", address(mrtDao));
        
        // 4. Deploy MRTPresale
        console.log("Deploying MRTPresale...");
        mrtPresale = new MRTPresale(
            address(mrtCollection),
            mrtTokenAddress,
            trustedOracle,
            usdtTokenAddress,
            address(mrtStaking), // staking contract
            communityWallet,     // community contract
            devWallet,           // dev wallet
            marketingWallet,     // marketing wallet
            teamWallet,          // team wallet
            address(mrtDao)      // DAO contract/treasury
        );
        console.log("MRTPresale deployed at:", address(mrtPresale));
        
        // 5. Update contract references
        console.log("Updating contract references...");

        // Set presale and DAO contracts in MRTCollection
        mrtCollection.setContractAddresses(address(mrtPresale), address(mrtDao));
        
        console.log("Set presale and DAO contracts in MRTCollection");
        
        // Set rarity URIs for the MRTCollection
        mrtCollection.setRarityURI(MRTCollection.Rarity.COMMON, "common/");
        mrtCollection.setRarityURI(MRTCollection.Rarity.UNCOMMON, "uncommon/");
        mrtCollection.setRarityURI(MRTCollection.Rarity.RARE, "rare/");
        mrtCollection.setRarityURI(MRTCollection.Rarity.EPIC, "epic/");
        mrtCollection.setRarityURI(MRTCollection.Rarity.LEGENDARY, "legendary/");
        console.log("Set rarity URIs for MRTCollection");
        
        // Transfer ownership of contracts if needed
        // This is optional - you might want the deployer to remain the owner initially
        // mrtCollection.transferOwnership(daoWallet);
        // mrtStaking.transferOwnership(daoWallet);
        // mrtPresale.transferOwnership(daoWallet);
        // mrtDao.transferOwnership(daoWallet);
        
        vm.stopBroadcast();
        
        console.log("MRT Ecosystem Deployment Complete!");
        console.log("MRTCollection:", address(mrtCollection));
        console.log("MRTStaking:", address(mrtStaking));
        console.log("MRTDAO:", address(mrtDao));
        console.log("MRTPresale:", address(mrtPresale));
    }
}