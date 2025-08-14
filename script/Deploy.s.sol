// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Your NEW paymaster implementation
import {SimplePrivacyPoolPaymaster} from "privacy-pool-paymasters-contracts/SimplePrivacyPoolPaymaster.sol";

// Real Privacy Pool contracts from submodule
import {Entrypoint} from "contracts/Entrypoint.sol";
import {PrivacyPoolSimple} from "contracts/implementations/PrivacyPoolSimple.sol";
import {WithdrawalVerifier} from "contracts/verifiers/WithdrawalVerifier.sol";
import {CommitmentVerifier} from "contracts/verifiers/CommitmentVerifier.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from '@oz/interfaces/IERC20.sol';

// Account Abstraction
import {IEntryPoint as IERC4337EntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IWithdrawalVerifier} from "privacy-pool-paymasters-contracts/interfaces/IWithdrawalVerifier.sol";

/**
 * @title Deploy
 * @notice E2E deployment script using functional test contracts
 * @dev These "mock" contracts implement the real interfaces and work for E2E testing
 *      In production, replace these with actual deployed privacy-pools-core addresses
 */
contract Deploy is Script {
    // ERC-4337 EntryPoint (standard across networks)
    address constant ERC4337_ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Privacy Pool Paymaster E2E Deployment ===");
        console.log("Deployer:", deployer);
        console.log("ERC-4337 EntryPoint:", ERC4337_ENTRYPOINT);
        console.log("");

        // 1. Deploy REAL ZK Verifiers
        console.log("1. Deploying REAL ZK Verifiers...");
        address withdrawalVerifier = address(new WithdrawalVerifier());
        address commitmentVerifier = address(new CommitmentVerifier());
        
        console.log("   Withdrawal Verifier:", withdrawalVerifier);
        console.log("   Commitment Verifier:", commitmentVerifier);

        // 2. Deploy Privacy Pool Entrypoint with proxy (UUPS upgradeable)
        console.log("2. Deploying Privacy Pool Entrypoint...");
        
        address privacyEntrypoint = address(new ERC1967Proxy(
            address(new Entrypoint()),
            abi.encodeCall(Entrypoint.initialize, (deployer, deployer))
        ));
        
        console.log("   Privacy Pool Entrypoint:", privacyEntrypoint);

        // 3. Deploy REAL ETH Privacy Pool
        console.log("3. Deploying ETH Privacy Pool...");
        address ethPrivacyPool = address(new PrivacyPoolSimple(
            privacyEntrypoint,
            withdrawalVerifier,
            commitmentVerifier
        ));
        console.log("   ETH Privacy Pool:", ethPrivacyPool);

        // 4. Register ETH Privacy Pool with Entrypoint
        console.log("4. Registering ETH Privacy Pool...");
        
        Entrypoint(payable(privacyEntrypoint)).registerPool(
            IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), // ETH
            IPrivacyPool(ethPrivacyPool),
            0.01 ether, // MIN_DEPOSIT
            100, // VETTING_FEE_BPS (1%)
            1000 // MAX_RELAY_FEE_BPS (10%)
        );
        console.log("   ETH Pool registered with Entrypoint");

        // 5. Deploy SimplePrivacyPoolPaymaster
        console.log("5. Deploying SimplePrivacyPoolPaymaster...");
        address payable paymaster = payable(address(new SimplePrivacyPoolPaymaster(
            IERC4337EntryPoint(ERC4337_ENTRYPOINT),
            IEntrypoint(privacyEntrypoint),
            IPrivacyPool(ethPrivacyPool)
        )));
        console.log("   Paymaster deployed:", paymaster);

        // 6. Configure expected smart account for deterministic pattern
        console.log("6. Configuring Expected Smart Account...");
        // NOTE: To get the correct address:
        // 1. Deploy a SimpleAccount using SimpleAccountFactory with the same private key
        //    used in your withdrawal scripts (e.g., Hardhat account #0)
        // 2. Use SimpleAccountFactory.getAddress(owner, salt) to get deterministic address
        // 3. Or run a withdrawal script once to deploy the account and use that address
        address expectedAccount = 0xa3aBDC7f6334CD3EE466A115f30522377787c024;
        SimplePrivacyPoolPaymaster(paymaster).setExpectedSmartAccount(expectedAccount);
        console.log("   Expected smart account set to:", expectedAccount);

        // 7. Fund paymaster for gas sponsorship
        console.log("7. Funding Paymaster...");
        SimplePrivacyPoolPaymaster(paymaster).deposit{value: 0.1 ether}();
        console.log("   Paymaster funded with 0.1 ETH");

        // 8. Verify deployment
        console.log("8. Verifying deployment...");
        require(paymaster.code.length > 0, "Paymaster deployment failed");
        require(ethPrivacyPool.code.length > 0, "Privacy Pool deployment failed");
        require(privacyEntrypoint.code.length > 0, "Entrypoint deployment failed");
        console.log("   All contracts deployed successfully");

        vm.stopBroadcast();

        // Output addresses for E2E script consumption
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Copy these addresses to your E2E script:");
        console.log("ENTRYPOINT:", privacyEntrypoint);
        console.log("PRIVACY_POOL:", ethPrivacyPool); 
        console.log("PAYMASTER:", paymaster);
        console.log("WITHDRAWAL_VERIFIER:", withdrawalVerifier);
        console.log("COMMITMENT_VERIFIER:", commitmentVerifier);
        console.log("");
    }
}