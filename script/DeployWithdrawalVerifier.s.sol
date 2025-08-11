// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";

/**
 * @title DeployWithdrawalVerifier
 * @notice Deployment script for the WithdrawalVerifier contract
 */
contract DeployWithdrawalVerifier is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy WithdrawalVerifier contract
        WithdrawalVerifier verifier = new WithdrawalVerifier();
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("WithdrawalVerifier deployed at:", address(verifier));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        return address(verifier);
    }
}
