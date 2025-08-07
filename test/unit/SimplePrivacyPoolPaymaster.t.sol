// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {TestBase} from "../TestBase.sol";
import {SimplePrivacyPoolPaymaster, IPrivacyPoolWithdrawalValidator} from "../../contracts/SimplePrivacyPoolPaymaster.sol";
import {IAccountValidator} from "../../contracts/validators/IAccountValidator.sol";
import {SimpleAccountValidator} from "../../contracts/validators/SimpleAccountValidator.sol";
import {PrivacyPoolWithdrawalValidator} from "../../contracts/validators/PrivacyPoolWithdrawalValidator.sol";
import {MockEntryPoint} from "../mocks/MockEntryPoint.sol";
import {MockPrivacyPool, MockEntrypoint, MockVerifier} from "../mocks/MockPrivacyPoolComponents.sol";

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";

/**
 * @title SimplePrivacyPoolPaymasterTest
 * @notice Unit tests for SimplePrivacyPoolPaymaster
 */
contract SimplePrivacyPoolPaymasterTest is TestBase {
    SimplePrivacyPoolPaymaster paymaster;
    MockEntryPoint mockErc4337EntryPoint;
    MockEntrypoint mockPrivacyEntrypoint;
    MockPrivacyPool mockEthPool;
    MockVerifier mockVerifier;
    SimpleAccountValidator accountValidator;
    PrivacyPoolWithdrawalValidator withdrawalValidator;

    // Test data
    address constant TEST_FACTORY = address(0x1234);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        // Deploy mock components
        mockErc4337EntryPoint = new MockEntryPoint();
        mockVerifier = new MockVerifier();
        mockEthPool = new MockPrivacyPool(address(mockVerifier));
        mockPrivacyEntrypoint = new MockEntrypoint(address(mockEthPool));

        // Deploy validators
        accountValidator = new SimpleAccountValidator(
            TEST_FACTORY,
            address(mockPrivacyEntrypoint)
        );

        // Deploy a temporary mock paymaster for withdrawal validator constructor
        MockSimplePaymaster mockPaymaster = new MockSimplePaymaster(
            address(mockPrivacyEntrypoint)
        );

        // Create withdrawal validator with mock paymaster
        PrivacyPoolWithdrawalValidator tempValidator = new PrivacyPoolWithdrawalValidator(
                payable(address(mockPaymaster))
            );

        // Deploy real paymaster
        paymaster = new SimplePrivacyPoolPaymaster(
            mockErc4337EntryPoint,
            IEntrypoint(address(mockPrivacyEntrypoint)),
            IPrivacyPool(address(mockEthPool)),
            IPrivacyPoolWithdrawalValidator(address(tempValidator))
        );

        // Deploy withdrawal validator with paymaster
        withdrawalValidator = new PrivacyPoolWithdrawalValidator(
            payable(address(paymaster))
        );

        // Set withdrawal validator in paymaster (cast to interface)
        paymaster.setWithdrawalValidator(
            IPrivacyPoolWithdrawalValidator(address(withdrawalValidator))
        );

        // Add supported factory to paymaster
        paymaster.addSupportedFactory(TEST_FACTORY, accountValidator);

        // Fund paymaster
        deal(address(paymaster), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(
            address(paymaster.entryPoint()),
            address(mockErc4337EntryPoint)
        );
        assertEq(
            address(paymaster.PRIVACY_POOL_ENTRYPOINT()),
            address(mockPrivacyEntrypoint)
        );
        assertEq(address(paymaster.ETH_PRIVACY_POOL()), address(mockEthPool));
        assertEq(paymaster.POST_OP_GAS_LIMIT(), POST_OP_GAS_LIMIT);
    }

    /*//////////////////////////////////////////////////////////////
                        FACTORY MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddSupportedFactory_Success() public {
        address newFactory = address(0x5678);
        SimpleAccountValidator newValidator = new SimpleAccountValidator(
            newFactory,
            address(mockPrivacyEntrypoint)
        );

        // Test contract is the owner, no need to prank
        paymaster.addSupportedFactory(newFactory, newValidator);

        assertEq(
            address(paymaster.accountValidators(newFactory)),
            address(newValidator)
        );
    }

    function test_AddSupportedFactory_ZeroAddress() public {
        expectRevert(SimplePrivacyPoolPaymaster.InvalidFactory.selector);
        paymaster.addSupportedFactory(address(0), accountValidator);
    }

    function test_AddSupportedFactory_ZeroValidator() public {
        expectRevert(SimplePrivacyPoolPaymaster.InvalidValidator.selector);
        paymaster.addSupportedFactory(
            address(0x5678),
            IAccountValidator(address(0))
        );
    }

    function test_AddSupportedFactory_AlreadyExists() public {
        expectRevert(
            SimplePrivacyPoolPaymaster.AccountFactoryAlreadySupported.selector
        );
        paymaster.addSupportedFactory(TEST_FACTORY, accountValidator);
    }

    function test_RemoveSupportedFactory_Success() public {
        paymaster.removeSupportedFactory(TEST_FACTORY);

        assertEq(
            address(paymaster.accountValidators(TEST_FACTORY)),
            address(0)
        );
    }

    function test_RemoveSupportedFactory_NotSupported() public {
        expectRevert(
            SimplePrivacyPoolPaymaster.UnsupportedAccountFactory.selector
        );
        paymaster.removeSupportedFactory(address(0x9999));
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATOR MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetWithdrawalValidator_Success() public {
        PrivacyPoolWithdrawalValidator newValidator = new PrivacyPoolWithdrawalValidator(
                payable(address(paymaster))
            );

        paymaster.setWithdrawalValidator(
            IPrivacyPoolWithdrawalValidator(address(newValidator))
        );

        assertEq(
            address(paymaster.WITHDRAWAL_VALIDATOR()),
            address(newValidator)
        );
    }

    function test_SetWithdrawalValidator_ZeroAddress() public {
        expectRevert(SimplePrivacyPoolPaymaster.InvalidValidator.selector);
        paymaster.setWithdrawalValidator(
            IPrivacyPoolWithdrawalValidator(address(0))
        );
    }

    /*//////////////////////////////////////////////////////////////
                    POST OP GAS LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ValidatePaymasterUserOp_InsufficientPostOpGasLimit() public {
        PackedUserOperation memory userOp = createTestUserOp();

        // Set postOpGasLimit to less than required (25,000 < 32,000)
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(300000), // verificationGasLimit
            uint128(25000) // postOpGasLimit - too low
        );

        vm.prank(address(mockErc4337EntryPoint));
        expectRevert(
            SimplePrivacyPoolPaymaster.InsufficientPostOpGasLimit.selector
        );
        paymaster.validatePaymasterUserOp(userOp, bytes32(0), 60000);
    }

    function test_ValidatePaymasterUserOp_SufficientPostOpGasLimit() public {
        PackedUserOperation memory userOp = createValidUserOp();

        // Set postOpGasLimit to exactly the minimum (32,000)
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(300000), // verificationGasLimit
            uint128(32000) // postOpGasLimit - exactly minimum
        );

        vm.prank(address(mockErc4337EntryPoint));
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(userOp, bytes32(0), 60000);

        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /*//////////////////////////////////////////////////////////////
                        FRESH ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ValidatePaymasterUserOp_ExistingAccountNotSupported() public {
        PackedUserOperation memory userOp = createTestUserOp();
        userOp.initCode = ""; // No initCode = existing account

        vm.prank(address(mockErc4337EntryPoint));
        expectRevert(
            SimplePrivacyPoolPaymaster.ExistingAccountNotSupported.selector
        );
        paymaster.validatePaymasterUserOp(userOp, bytes32(0), 60000);
    }

    function test_ValidatePaymasterUserOp_UnsupportedAccountFactory() public {
        PackedUserOperation memory userOp = createTestUserOp();

        // Use unsupported factory in initCode
        address unsupportedFactory = address(0x9999);
        userOp.initCode = abi.encodePacked(
            unsupportedFactory,
            "some_init_data"
        );

        vm.prank(address(mockErc4337EntryPoint));
        expectRevert(
            SimplePrivacyPoolPaymaster.UnsupportedAccountFactory.selector
        );
        paymaster.validatePaymasterUserOp(userOp, bytes32(0), 60000);
    }

    /*//////////////////////////////////////////////////////////////
                    VALIDATION SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ValidatePaymasterUserOp_Success() public {
        PackedUserOperation memory userOp = createValidUserOp();

        vm.prank(address(mockErc4337EntryPoint));
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(userOp, bytes32(0), 60000);

        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /*//////////////////////////////////////////////////////////////
                        ECONOMIC VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EconomicValidation_InvalidRelayData() public {
        PackedUserOperation memory userOp = createValidUserOp();

        // Create invalid relay calldata (missing proper relay structure)
        bytes memory invalidRelayData = "invalid_relay_data";
        userOp.callData = createExecuteCalldata(
            address(mockPrivacyEntrypoint),
            0,
            invalidRelayData
        );

        vm.prank(address(mockErc4337EntryPoint));
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(userOp, bytes32(0), 60000);

        // Should return validation failure (packed validation data with failure flag)
        assertTrue(
            validationData != 0,
            "Validation should fail for invalid relay data"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit() public {
        uint256 depositAmount = 5 ether;
        uint256 initialBalance = mockErc4337EntryPoint.balanceOf(
            address(paymaster)
        );

        vm.deal(ALICE, depositAmount);
        vm.prank(ALICE);
        paymaster.deposit{value: depositAmount}();

        assertEq(
            mockErc4337EntryPoint.balanceOf(address(paymaster)),
            initialBalance + depositAmount,
            "Deposit should increase EntryPoint balance"
        );
    }

    function test_WithdrawTo() public {
        // First deposit some funds
        uint256 depositAmount = 5 ether;
        vm.deal(address(paymaster), depositAmount);
        mockErc4337EntryPoint.depositTo{value: depositAmount}(
            address(paymaster)
        );

        uint256 withdrawAmount = 2 ether;
        uint256 initialBalance = BOB.balance;

        paymaster.withdrawTo(payable(BOB), withdrawAmount);

        assertEq(
            BOB.balance,
            initialBalance + withdrawAmount,
            "Withdrawal should transfer ETH to recipient"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createTestUserOp()
        internal
        view
        returns (PackedUserOperation memory)
    {
        return
            PackedUserOperation({
                sender: ALICE,
                nonce: 0,
                initCode: abi.encodePacked(TEST_FACTORY, "init_data"),
                callData: createExecuteCalldata(
                    address(mockPrivacyEntrypoint),
                    0,
                    "test_data"
                ),
                accountGasLimits: bytes32(
                    (uint256(300000) << 128) | uint256(300000)
                ),
                preVerificationGas: 50000,
                gasFees: bytes32((uint256(20 gwei) << 128) | uint256(20 gwei)),
                paymasterAndData: abi.encodePacked(
                    address(paymaster),
                    uint128(300000), // verificationGasLimit
                    uint128(35000) // postOpGasLimit
                ),
                signature: ""
            });
    }

    function createValidUserOp()
        internal
        view
        returns (PackedUserOperation memory)
    {
        // Create withdrawal struct for paymaster scenario
        IPrivacyPool.Withdrawal memory withdrawal = _createPaymasterWithdrawal();

        // Generate realistic withdrawal proof
        ProofLib.WithdrawProof memory proof = _generateWithdrawalProofForPaymaster();
        
        // Use scope from mock pool
        uint256 scope = mockEthPool.SCOPE();

        // Build the inner callData for entrypoint.relay()
        bytes memory relayCallData = abi.encodeCall(
            IEntrypoint.relay,
            (withdrawal, proof, scope)
        );

        // Build the callData for userAccount.execute()
        bytes memory callData = abi.encodeWithSelector(
            0xb61d27f6, // SimpleAccount.execute selector
            address(mockPrivacyEntrypoint), // dest: Privacy Pool Entrypoint
            0, // value: 0 ETH (no ETH sent with call)
            relayCallData // func: encoded relay call
        );

        // Create UserOperation with proper paymasterAndData format
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster), // paymaster address (20 bytes)
            uint128(300000), // verificationGasLimit for paymaster (16 bytes)
            uint128(35000) // postOpGasLimit (16 bytes) - above minimum for tests
        );

        return PackedUserOperation({
            sender: ALICE,
            nonce: 0,
            initCode: abi.encodePacked(TEST_FACTORY, "init_data"), // Fresh account support
            callData: callData,
            accountGasLimits: bytes32(
                (uint256(300000) << 128) | uint256(300000)
            ), // verificationGasLimit | callGasLimit
            preVerificationGas: 50000,
            gasFees: bytes32((uint256(20 gwei) << 128) | uint256(20 gwei)), // maxPriorityFeePerGas | maxFeePerGas
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    /**
     * @notice Create withdrawal struct for paymaster scenario
     */
    function _createPaymasterWithdrawal()
        internal
        view
        returns (IPrivacyPool.Withdrawal memory)
    {
        // Build RelayData for paymaster flow
        IEntrypoint.RelayData memory relayData = IEntrypoint.RelayData({
            recipient: BOB, // User account receives ETH
            feeRecipient: address(paymaster), // Paymaster receives fees
            relayFeeBPS: 100 // 1% fee
        });

        return
            IPrivacyPool.Withdrawal({
                processooor: address(mockPrivacyEntrypoint), // Privacy entrypoint processes
                data: abi.encode(relayData) // Encoded relay data
            });
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_PostOpGasLimit_BelowMinimum(uint128 gasLimit) public {
        vm.assume(gasLimit < POST_OP_GAS_LIMIT);

        PackedUserOperation memory userOp = createTestUserOp();
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(300000),
            gasLimit
        );

        vm.prank(address(mockErc4337EntryPoint));
        expectRevert(
            SimplePrivacyPoolPaymaster.InsufficientPostOpGasLimit.selector
        );
        paymaster.validatePaymasterUserOp(userOp, bytes32(0), 60000);
    }

    function testFuzz_PostOpGasLimit_AboveMinimum(uint128 gasLimit) public {
        vm.assume(
            gasLimit >= POST_OP_GAS_LIMIT && gasLimit <= type(uint128).max
        );

        PackedUserOperation memory userOp = createValidUserOp();
        userOp.paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(300000),
            gasLimit
        );

        vm.prank(address(mockErc4337EntryPoint));
        (bytes memory context, uint256 validationData) = paymaster
            .validatePaymasterUserOp(userOp, bytes32(0), 60000);

        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /*//////////////////////////////////////////////////////////////
                        PROOF GENERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generate realistic withdrawal proof for paymaster testing
     */
    function _generateWithdrawalProofForPaymaster()
        internal
        view
        returns (ProofLib.WithdrawProof memory proof)
    {
        // Create withdrawal and calculate context
        IPrivacyPool.Withdrawal memory withdrawal = _createPaymasterWithdrawal();
        uint256 context = uint256(
            keccak256(abi.encode(withdrawal, mockEthPool.SCOPE()))
        ) % 21888242871839275222246405745257275088548364400416034343698204186575808495617; // SNARK_SCALAR_FIELD
        
        // Create realistic Groth16 proof values
        proof.pA[0] = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        proof.pA[1] = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;
        proof.pB[0][0] = 0x1111111111111111111111111111111111111111111111111111111111111111;
        proof.pB[0][1] = 0x2222222222222222222222222222222222222222222222222222222222222222;
        proof.pB[1][0] = 0x3333333333333333333333333333333333333333333333333333333333333333;
        proof.pB[1][1] = 0x4444444444444444444444444444444444444444444444444444444444444444;
        proof.pC[0] = 0x5555555555555555555555555555555555555555555555555555555555555555;
        proof.pC[1] = 0x6666666666666666666666666666666666666666666666666666666666666666;
        
        // Set public signals for withdrawal proof
        proof.pubSignals[0] = uint256(keccak256("new_commitment_hash_paymaster")); // newCommitmentHash
        proof.pubSignals[1] = uint256(keccak256("existing_nullifier_hash_paymaster")); // existingNullifierHash  
        proof.pubSignals[2] = 50 ether; // withdrawnValue: 50 ETH
        proof.pubSignals[3] = uint256(keccak256("state_root_paymaster")); // stateRoot
        proof.pubSignals[4] = 32; // stateTreeDepth
        proof.pubSignals[5] = uint256(keccak256("asp_root_paymaster")); // ASPRoot
        proof.pubSignals[6] = 32; // ASPTreeDepth
        proof.pubSignals[7] = context; // context
    }
}

// Simple mock paymaster for testing validator construction
contract MockSimplePaymaster {
    address public immutable PRIVACY_POOL_ENTRYPOINT;

    constructor(address _privacyEntrypoint) {
        PRIVACY_POOL_ENTRYPOINT = _privacyEntrypoint;
    }
}
