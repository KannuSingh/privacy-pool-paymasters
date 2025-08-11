// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimpleAccountValidator} from "../src/contracts/validators/SimpleAccountValidator.sol";

/**
 * @title DeployAccountValidator
 * @notice Deployment script for the SimpleAccountValidator contract
 * @dev Requires privacy pool entrypoint address and optionally SimpleAccount factory address
 */
contract DeployAccountValidator is Script {
    
    // Default SimpleAccount Factory address (can be overridden with env var)
    address constant DEFAULT_SIMPLE_ACCOUNT_FACTORY = 0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985;
    
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get required addresses from environment
        address privacyEntrypoint = vm.envAddress("ENTRYPOINT_ADDRESS");
        
        // Get SimpleAccount factory address (with default fallback)
        address simpleAccountFactory;
        try vm.envAddress("SIMPLE_ACCOUNT_FACTORY_ADDRESS") returns (address factory) {
            simpleAccountFactory = factory;
        } catch {
            simpleAccountFactory = DEFAULT_SIMPLE_ACCOUNT_FACTORY;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy SimpleAccountValidator contract
        SimpleAccountValidator validator = new SimpleAccountValidator(
            simpleAccountFactory,
            privacyEntrypoint
        );
        
        vm.stopBroadcast();
        
        // Essential logs
        console.log("SimpleAccountValidator deployed at:", address(validator));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("SimpleAccount Factory:", simpleAccountFactory);
        console.log("Privacy Entrypoint:", privacyEntrypoint);
        
        return address(validator);
    }
}
