// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimplePrivacyPoolPaymaster} from "../src/contracts/SimplePrivacyPoolPaymaster.sol";
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";

/**
 * @title DeployPaymaster
 * @notice Deployment script for the SimplePrivacyPoolPaymaster contract
 * @dev Requires ERC4337 entrypoint, privacy pool entrypoint, and ETH privacy pool addresses
 */
contract DeployPaymaster is Script {
    
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get required addresses from environment
        address privacyEntrypoint = vm.envAddress("ENTRYPOINT_ADDRESS");
        address ethPrivacyPool = vm.envAddress("PRIVACY_POOL_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimplePrivacyPoolPaymaster contract
        SimplePrivacyPoolPaymaster paymaster = new SimplePrivacyPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IEntrypoint(privacyEntrypoint),
            IPrivacyPool(ethPrivacyPool)
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("SimplePrivacyPoolPaymaster deployed at:", address(paymaster));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("ERC4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("Privacy Entrypoint:", privacyEntrypoint);
        console.log("ETH Privacy Pool:", ethPrivacyPool);
        
        return address(paymaster);
    }
}
