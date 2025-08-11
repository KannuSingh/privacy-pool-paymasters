// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";

/**
 * @title DeployCommitmentVerifier
 * @notice Deployment script for the CommitmentVerifier contract
 */
contract DeployCommitmentVerifier is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy CommitmentVerifier contract
        CommitmentVerifier verifier = new CommitmentVerifier();
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("CommitmentVerifier deployed at:", address(verifier));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        return address(verifier);
    }
}
