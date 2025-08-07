// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {TestBase} from "../TestBase.sol";
import {PrivacyPoolWithdrawalValidator} from "../../contracts/validators/PrivacyPoolWithdrawalValidator.sol";
import {MockSimplePrivacyPoolPaymaster} from "../mocks/MockSimplePrivacyPoolPaymaster.sol";
import {MockEntrypoint, MockVerifier, MockPrivacyPool} from "../mocks/MockPrivacyPoolComponents.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";

/**
 * @title PrivacyPoolWithdrawalValidatorTest
 * @notice Unit tests for PrivacyPoolWithdrawalValidator
 */
contract PrivacyPoolWithdrawalValidatorTest is TestBase {
    PrivacyPoolWithdrawalValidator validator;
    MockSimplePrivacyPoolPaymaster mockPaymaster;
    MockEntrypoint mockEntrypoint;
    MockVerifier mockVerifier;
    MockPrivacyPool mockPool;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        // Deploy actual mock contracts instead of using constant addresses
        mockVerifier = new MockVerifier();
        mockPool = new MockPrivacyPool(address(mockVerifier));
        mockEntrypoint = new MockEntrypoint(address(mockPool));
        
        mockPaymaster = new MockSimplePrivacyPoolPaymaster(
            address(mockEntrypoint)
        );
        validator = new PrivacyPoolWithdrawalValidator(
            payable(address(mockPaymaster))
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(address(validator.PAYMASTER()), address(mockPaymaster));
        assertEq(
            address(validator.PRIVACY_POOL_ENTRYPOINT()),
            address(mockEntrypoint)
        );
        assertEq(validator.paymaster(), address(mockPaymaster));
        assertEq(validator.entrypoint(), address(mockEntrypoint));
    }

    /*//////////////////////////////////////////////////////////////
                          VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ValidateWithdrawal_Success() public {
        // Create mock relay calldata with proper structure
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: BOB, // The recipient/processor of the withdrawal
            data: "" // Additional data for the withdrawal
        });

        ProofLib.WithdrawProof memory proof;
        uint256 scope = 1;

        bytes memory relayCalldata = abi.encodeCall(
            mockEntrypoint.relay,
            (withdrawal, proof, scope)
        );

        // Call through the mock paymaster (which should call the validator)
        vm.prank(address(mockPaymaster));
        validator.validateWithdrawal(address(mockEntrypoint), 0, relayCalldata);
    }

    function test_ValidateWithdrawal_InvalidCaller() public {
        bytes memory mockData = "test";

        // Should revert when called by non-paymaster
        vm.prank(ALICE);
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidCaller.selector);
        validator.validateWithdrawal(MOCK_PRIVACY_ENTRYPOINT, 0, mockData);
    }

    function test_ValidateWithdrawal_InvalidTarget() public {
        bytes memory mockData = "test";

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidTarget.selector);
        validator.validateWithdrawal(ALICE, 0, mockData); // Wrong target
    }

    function test_ValidateWithdrawal_InvalidValue() public {
        bytes memory mockData = "test";

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidValue.selector);
        validator.validateWithdrawal(
            address(mockEntrypoint),
            1 ether,
            mockData
        ); // Non-zero value
    }

    function test_ValidateWithdrawal_ValidationFailed_RelayFails() public {
        // Set mock entrypoint to fail relay validation
        mockEntrypoint.setShouldRelaySucceed(false);

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: BOB,
            data: ""
        });
        ProofLib.WithdrawProof memory proof;
        uint256 scope = 1;

        bytes memory relayCalldata = abi.encodeCall(
            mockEntrypoint.relay,
            (withdrawal, proof, scope)
        );

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.ValidationFailed.selector);
        validator.validateWithdrawal(address(mockEntrypoint), 0, relayCalldata);
    }

    function test_ValidateWithdrawal_ValidationFailed_WithdrawFails() public {
        // Create withdrawal with invalid processooor (zero address) to trigger failure
        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(0), // This will fail in the mock
            data: ""
        });
        ProofLib.WithdrawProof memory proof;
        uint256 scope = 1;

        bytes memory relayCalldata = abi.encodeCall(
            mockEntrypoint.relay,
            (withdrawal, proof, scope)
        );

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.ValidationFailed.selector);
        validator.validateWithdrawal(address(mockEntrypoint), 0, relayCalldata);
    }

    function test_ValidateWithdrawal_ValidationFailed_InvalidCalldata() public {
        bytes memory invalidCalldata = "invalid";

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.ValidationFailed.selector);
        validator.validateWithdrawal(
            address(mockEntrypoint),
            0,
            invalidCalldata
        );
    }

    /*//////////////////////////////////////////////////////////////
                            RELAY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Relay_InvalidCaller() public {
        // Test that the validator rejects calls from non-paymaster
        vm.prank(ALICE);
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidCaller.selector);
        validator.validateWithdrawal(address(mockEntrypoint), 0, "test");
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Paymaster() public view {
        assertEq(validator.paymaster(), address(mockPaymaster));
    }

    function test_Entrypoint() public view {
        assertEq(validator.entrypoint(), address(mockEntrypoint));
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ValidateWithdrawal_InvalidTarget(
        address invalidTarget
    ) public {
        vm.assume(invalidTarget != address(mockEntrypoint));
        bytes memory mockData = "test";

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidTarget.selector);
        validator.validateWithdrawal(invalidTarget, 0, mockData);
    }

    function testFuzz_ValidateWithdrawal_InvalidValue(
        uint256 invalidValue
    ) public {
        vm.assume(invalidValue != 0);
        bytes memory mockData = "test";

        vm.prank(address(mockPaymaster));
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidValue.selector);
        validator.validateWithdrawal(
            address(mockEntrypoint),
            invalidValue,
            mockData
        );
    }

    function testFuzz_ValidateWithdrawal_InvalidCaller(address caller) public {
        vm.assume(caller != address(mockPaymaster));
        bytes memory mockData = "test";

        vm.prank(caller);
        expectRevert(PrivacyPoolWithdrawalValidator.InvalidCaller.selector);
        validator.validateWithdrawal(address(mockEntrypoint), 0, mockData);
    }
}
