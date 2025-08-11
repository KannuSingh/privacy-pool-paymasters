// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Entrypoint} from "contracts/Entrypoint.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployEntrypoint
 * @notice Deployment script for the Privacy Pool Entrypoint with UUPS proxy
 */
contract DeployEntrypoint is Script {
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Entrypoint implementation
        Entrypoint implementation = new Entrypoint();
        
        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(Entrypoint.initialize, (deployer, deployer))
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("Entrypoint implementation deployed at:", address(implementation));
        console.log("Entrypoint proxy deployed at:", address(proxy));
        console.log("Deployer:", deployer);
        
        return address(proxy);
    }
}
