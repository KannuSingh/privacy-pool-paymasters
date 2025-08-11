// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PrivacyPoolSimple} from "contracts/implementations/PrivacyPoolSimple.sol";
import {Entrypoint} from "contracts/Entrypoint.sol";
import {IERC20} from '@oz/interfaces/IERC20.sol';
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {Constants} from "contracts/lib/Constants.sol";

/**
 * @title DeployPrivacyPool
 * @notice Deployment script for the PrivacyPoolSimple contract with Entrypoint registration
 * @dev Requires entrypoint, withdrawalVerifier, and commitmentVerifier addresses
 */
contract DeployPrivacyPool is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get required addresses from environment
        address payable entrypoint = payable(vm.envAddress("ENTRYPOINT_ADDRESS"));
        address withdrawalVerifier = vm.envAddress("WITHDRAWAL_VERIFIER_ADDRESS");
        address commitmentVerifier = vm.envAddress("COMMITMENT_VERIFIER_ADDRESS");
        
        // Get configuration from environment variables with defaults
        uint256 minimumDepositAmount = vm.envOr("MINIMUM_DEPOSIT_AMOUNT", uint256(0.001 ether)); // Default: 0.001 ETH
        uint256 vettingFeeBPS = vm.envOr("VETTING_FEE_BPS", uint256(100)); // Default: 1% (100 basis points)
        uint256 maxRelayFeeBPS = vm.envOr("MAX_RELAY_FEE_BPS", uint256(1500)); // Default: 5% (500 basis points)
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy PrivacyPoolSimple contract
        PrivacyPoolSimple privacyPool = new PrivacyPoolSimple(
            entrypoint,
            withdrawalVerifier,
            commitmentVerifier
        );
        
        // Register the pool with the Entrypoint
        Entrypoint entrypointContract = Entrypoint(entrypoint);
        entrypointContract.registerPool(
            IERC20(Constants.NATIVE_ASSET), // ETH asset
            IPrivacyPool(address(privacyPool)),
            minimumDepositAmount,
            vettingFeeBPS,
            maxRelayFeeBPS
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("PrivacyPoolSimple deployed at:", address(privacyPool));
        console.log("Pool registered with Entrypoint:", entrypoint);
        console.log("Minimum deposit amount:", minimumDepositAmount);
        console.log("Vetting fee (BPS):", vettingFeeBPS);
        console.log("Max relay fee (BPS):", maxRelayFeeBPS);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        return address(privacyPool);
    }
}
