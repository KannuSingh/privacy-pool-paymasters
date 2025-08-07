// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {TestBase} from "./TestBase.sol";
import {SimplePrivacyPoolPaymaster, IPrivacyPoolWithdrawalValidator} from "../contracts/SimplePrivacyPoolPaymaster.sol";
import {PrivacyPoolWithdrawalValidator} from "../contracts/validators/PrivacyPoolWithdrawalValidator.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";
import {MockPrivacyPool, MockEntrypoint, MockVerifier} from "./mocks/MockPrivacyPoolComponents.sol";

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";

/**
 * @title SimplePaymasterDeployTest
 * @notice Basic deployment test to isolate setup issues
 */
contract SimplePaymasterDeployTest is TestBase {
    MockEntryPoint mockErc4337EntryPoint;
    MockEntrypoint mockPrivacyEntrypoint;
    MockPrivacyPool mockEthPool;
    MockVerifier mockVerifier;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy mock components step by step
        mockErc4337EntryPoint = new MockEntryPoint();
        mockVerifier = new MockVerifier();
        mockEthPool = new MockPrivacyPool(address(mockVerifier));
        mockPrivacyEntrypoint = new MockEntrypoint(address(mockEthPool));
    }
    
    function test_DeployMocksOnly() public view {
        // Test that our mocks deploy correctly
        assertEq(mockEthPool.WITHDRAWAL_VERIFIER(), address(mockVerifier));
        assertEq(mockEthPool.SCOPE(), 1);
        assertEq(mockPrivacyEntrypoint.ETH_PRIVACY_POOL(), address(mockEthPool));
    }
    
    function test_DeployValidatorOnly() public {
        // Test validator deployment with proper mock
        MockSimplePaymaster mockPaymaster = new MockSimplePaymaster(address(mockPrivacyEntrypoint));
        
        PrivacyPoolWithdrawalValidator validator = new PrivacyPoolWithdrawalValidator(
            payable(address(mockPaymaster))
        );
        
        // Basic assertions
        assertEq(address(validator.PAYMASTER()), address(mockPaymaster));
        assertEq(address(validator.PRIVACY_POOL_ENTRYPOINT()), address(mockPrivacyEntrypoint));
    }
}

// Simple mock paymaster for testing validator construction
contract MockSimplePaymaster {
    address public immutable PRIVACY_POOL_ENTRYPOINT;
    
    constructor(address _privacyEntrypoint) {
        PRIVACY_POOL_ENTRYPOINT = _privacyEntrypoint;
    }
}