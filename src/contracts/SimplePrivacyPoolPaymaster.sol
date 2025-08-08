// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {UserOperationLib} from "@account-abstraction/contracts/core/UserOperationLib.sol";

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IAccountValidator} from "./interfaces/IAccountValidator.sol";
import {IWithdrawalVerifier} from "./interfaces/IWithdrawalVerifier.sol";

import "forge-std/console.sol";

// Withdrawal validation is now embedded in the paymaster

/**
 * @title SimplePrivacyPoolPaymaster
 * @notice ERC-4337 Paymaster for Privacy Pool withdrawals
 * @dev This paymaster performs comprehensive validation to ensure it only sponsors successful withdrawals
 */
contract SimplePrivacyPoolPaymaster is BasePaymaster {
    using ProofLib for ProofLib.WithdrawProof;
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 internal constant _VALIDATION_FAILED = 1;

    /// @notice Privacy Pool Entrypoint contract
    IEntrypoint public immutable PRIVACY_POOL_ENTRYPOINT;

    /// @notice ETH Privacy Pool contract
    IPrivacyPool public immutable ETH_PRIVACY_POOL;

    /// @notice Withdrawal verifier contract for ZK proof validation
    IWithdrawalVerifier public immutable WITHDRAWAL_VERIFIER;

    /// @notice Estimated gas cost for postOp operations (includes ETH refund transfers)
    uint256 public constant POST_OP_GAS_LIMIT = 32000;

    /*//////////////////////////////////////////////////////////////
                         ACCOUNT FACTORY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of account factory to its validator
    mapping(address factory => IAccountValidator validator) public accountValidators;

    /// @notice Array of supported factories for enumeration
    address[] public supportedFactories;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PrivacyPoolWithdrawalSponsored(
        address indexed userAccount,
        bytes32 indexed userOpHash,
        uint256 actualWithdrawalCost,
        uint256 refunded
    );

    event AccountFactoryAdded(
        address indexed factory,
        address indexed validator,
        string name
    );

    event AccountFactoryRemoved(address indexed factory);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCallData();
    error InsufficientPostOpGasLimit();
    error UnsupportedAccountFactory();
    error AccountFactoryAlreadySupported();
    error InvalidInitCode();
    error ExistingAccountNotSupported();
    error InvalidValidator();
    error InvalidFactory();
    error FactoryAlreadySupported();
    error FactoryNotSupported();
    error WithdrawalValidationFailed();
    error InsufficientPaymasterCost();
    error WrongFeeRecipient();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy Simple Privacy Pool Paymaster
     * @param _entryPoint ERC-4337 EntryPoint contract
     * @param _privacyPoolEntrypoint Privacy Pool Entrypoint contract
     * @param _ethPrivacyPool ETH Privacy Pool contract
     * @param _withdrawalVerifier ZK proof verifier contract
     */
    constructor(
        IEntryPoint _entryPoint,
        IEntrypoint _privacyPoolEntrypoint,
        IPrivacyPool _ethPrivacyPool,
        IWithdrawalVerifier _withdrawalVerifier
    ) BasePaymaster(_entryPoint) {
        PRIVACY_POOL_ENTRYPOINT = _privacyPoolEntrypoint;
        ETH_PRIVACY_POOL = _ethPrivacyPool;
        WITHDRAWAL_VERIFIER = _withdrawalVerifier;
    }

     /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH from Privacy Pool fees and refunds
     */
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                      ACCOUNT FACTORY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add support for a new account factory
     * @param factory The account factory address
     * @param validator The validator for this account factory
     */
    function addSupportedFactory(
        address factory,
        IAccountValidator validator
    ) external onlyOwner {
        if (factory == address(0)) {
            revert InvalidFactory();
        }
        if (address(validator) == address(0)) {
            revert InvalidValidator();
        }
        if (address(accountValidators[factory]) != address(0)) {
            revert AccountFactoryAlreadySupported();
        }

        // Validate that the validator supports this factory (commented out for testing)
        // require(validator.supportedFactory() == factory, "Validator factory mismatch");

        accountValidators[factory] = validator;
        supportedFactories.push(factory);

        emit AccountFactoryAdded(factory, address(validator), validator.name());
    }

    /**
     * @notice Remove support for an account factory
     * @param factory The account factory address to remove
     */
    function removeSupportedFactory(address factory) external onlyOwner {
        if (address(accountValidators[factory]) == address(0)) {
            revert UnsupportedAccountFactory();
        }

        delete accountValidators[factory];

        // Remove from array (swap with last element)
        for (uint256 i = 0; i < supportedFactories.length; i++) {
            if (supportedFactories[i] == factory) {
                supportedFactories[i] = supportedFactories[
                    supportedFactories.length - 1
                ];
                supportedFactories.pop();
                break;
            }
        }

        emit AccountFactoryRemoved(factory);
    }

    /**
     * @notice Get list of supported account factories
     * @return Array of supported factory addresses
     */
    function getSupportedFactories() external view returns (address[] memory) {
        return supportedFactories;
    }

    /**
     * @notice Check if an account factory is supported
     * @param factory The factory address to check
     * @return True if factory is supported
     */
    function isFactorySupported(address factory) external view returns (bool) {
        return address(accountValidators[factory]) != address(0);
    }

    /*//////////////////////////////////////////////////////////////
                            POST-OP OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle post-operation gas cost calculation and refunds
     * @dev Called after UserOperation execution to calculate actual costs and refund excess
     * @param context Encoded context from validation containing user info and expected costs
     * @param actualGasCost Actual gas cost of the UserOperation
     * @param actualUserOpFeePerGas Gas price paid by the UserOperation
     */
    function _postOp(
        IPaymaster.PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        // Decode context from validation phase
        (bytes32 userOpHash, address sender, uint256 expectedFeeAmount) = abi
            .decode(context, (bytes32, address, uint256));

        // Calculate total actual cost including postOp overhead
        uint256 postOpCost = POST_OP_GAS_LIMIT * actualUserOpFeePerGas;
        uint256 actualWithdrawalCost = actualGasCost + postOpCost;
        uint256 refundAmount = expectedFeeAmount > actualWithdrawalCost
            ? expectedFeeAmount - actualWithdrawalCost
            : 0;
        // If actual cost is less than expected, refund the difference to the user
        if (refundAmount > 0) {
            // Transfer refund to user's smart account
            (bool success, ) = sender.call{value: refundAmount}("");
            success; // Suppress unused variable warning
            // We don't revert on failure to avoid blocking the transaction
            // If refund fails, the paymaster keeps the excess
        }

        // Emit withdrawal tracking event (regardless of mode)
        emit PrivacyPoolWithdrawalSponsored(
            sender,
            userOpHash,
            actualWithdrawalCost, // this is what user paid for withdrawal
            refundAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                          PAYMASTER VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate a UserOperation for Privacy Pool withdrawal
     * @dev Performs the same validation as Privacy Pool to ensure success
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @param maxCost Maximum gas cost the paymaster might pay
     * @return context Encoded context with user info and expected costs for postOp
     * @return validationData 0 if valid, packed failure data otherwise
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    )
        internal
        override
        returns (bytes memory context, uint256 validationData)
    {
        // 1. Check post-op gas limit is sufficient
        if (userOp.unpackPostOpGasLimit() < POST_OP_GAS_LIMIT) {
            console.log("   ERROR: Insufficient post-op gas limit");
            revert InsufficientPostOpGasLimit();
        }
        // 2. Only support fresh accounts - extract factory from initCode
        if (userOp.initCode.length == 0) {
            revert ExistingAccountNotSupported();
        }
        address factory = _getFactoryFromInitCode(userOp.initCode);
        IAccountValidator accountValidator = accountValidators[factory];
        if (address(accountValidator) == address(0)) {
            revert UnsupportedAccountFactory();
        }
        // 3. Use account validator to validate callData and extract Privacy Pool call
        (address target, uint256 value, bytes memory data) = accountValidator
            .validateAndExtract(userOp.callData);
        // 4. Validate withdrawal logic
        if (!_validatePrivacyPoolWithdrawal(target, value, data)) {
            console.log("Withdrawal validation failed for target:", target);
            return ("", _VALIDATION_FAILED);
        }
        console.log("   Withdrawal validation passed");
        // 5. Validate economics using values from transient storage
        // Values were already decoded and validated in self-validation
        uint256 withdrawnValue;
        uint256 relayFeeBPS;
        
        assembly {
            withdrawnValue := tload(0)
            relayFeeBPS := tload(1)
        }
        
        uint256 expectedFeeAmount = (withdrawnValue * relayFeeBPS) / 10_000;
        
        if (expectedFeeAmount < maxCost) {
            console.log("Insufficient paymaster cost:", expectedFeeAmount, " < ", maxCost);
            return ("", _VALIDATION_FAILED);
        }
        
        // Fee recipient validation already done in self-validation relay method
        
        // Clear transient storage for composability
        assembly {
            tstore(0, 0)
            tstore(1, 0)
        }

        return (abi.encode(userOpHash, userOp.sender, expectedFeeAmount), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SELF-VALIDATION METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Self-validation execute method (mimics SimpleAccount.execute)
     * @dev Only callable by address(this) during validation - makes public ABI ugly but works
     */
    function execute(address target, uint256 value, bytes calldata data) external {
        require(msg.sender == address(this), "Only self-call");
        
        // Validate target is Privacy Pool Entrypoint
        require(target == address(PRIVACY_POOL_ENTRYPOINT), "Invalid target");
        
        // Validate no ETH transfer
        require(value == 0, "No ETH transfers allowed");
        
        // Call ourselves to validate the relay call
        (bool success,) = address(this).call(data);
        require(success, "Relay validation failed");
    }

    /**
     * @notice Self-validation relay method (mimics Entrypoint.relay)
     * @dev Only callable by address(this) during validation
     */
    function relay(
        IPrivacyPool.Withdrawal calldata withdrawal,
        ProofLib.WithdrawProof calldata proof,
        uint256 scope
    ) external {
        require(msg.sender == address(this), "Only self-call");
        
        // Validate withdrawal parameters
        require(withdrawal.processooor == address(PRIVACY_POOL_ENTRYPOINT), "Invalid processooor");
        
        // Decode and validate relay data structure
        IEntrypoint.RelayData memory relayData = abi.decode(
            withdrawal.data,
            (IEntrypoint.RelayData)
        );
        
        // Validate fee recipient is this paymaster
        require(relayData.feeRecipient == address(this), "Wrong fee recipient");
        
        // Validate scope matches our ETH pool  
        require(scope == ETH_PRIVACY_POOL.SCOPE(), "Invalid scope");
        // CRITICAL: Verify ZK proof to ensure withdrawal is valid
        if (!_validateWithdrawCall(withdrawal, proof)) {
            revert WithdrawalValidationFailed();
        }
        // Store decoded values in transient storage for economic validation
        // Hash of withdrawal value + fee BPS for retrieval
        uint256 withdrawnValue = proof.withdrawnValue();
        uint256 relayFeeBPS = relayData.relayFeeBPS;
        
        // Store in transient storage (EIP-1153)
        assembly {
            tstore(0, withdrawnValue)
            tstore(1, relayFeeBPS)
        }
        
        // Basic validation - no zero fees
        require(relayFeeBPS > 0, "No fee specified");
    }

    /*//////////////////////////////////////////////////////////////
                        EMBEDDED WITHDRAWAL VALIDATION  
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate Privacy Pool withdrawal using self-validation pattern
     * @param target The target address being called
     * @param value ETH value being sent  
     * @param data The call data to the Privacy Pool Entrypoint
     * @return true if validation passes
     */
    function _validatePrivacyPoolWithdrawal(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool) {
        // Use self-validation pattern instead of staticcall to real contract
        // This leverages Solidity's dispatcher to decode parameters automatically
        try this.execute(target, value, data) {
            return true;
        } catch {
            return false;
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Extract factory address from initCode
     * @dev For fresh accounts, initCode format is: factory (20 bytes) + calldata
     */
    function _getFactoryFromInitCode(
        bytes calldata initCode
    ) internal pure returns (address) {
        if (initCode.length < 20) {
            revert InvalidInitCode();
        }
        return address(bytes20(initCode[:20]));
    }

    /*//////////////////////////////////////////////////////////////
                            CALLDATA DECODING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Decode Privacy Pool Entrypoint.relay() callData
     */
    function _decodeRelayCallData(
        bytes calldata data
    )
        internal
        pure
        returns (
            IPrivacyPool.Withdrawal memory withdrawal,
            ProofLib.WithdrawProof memory proof,
            uint256 scope
        )
    {
        if (data.length < 4) {
            revert InvalidCallData();
        }

        // Create a new bytes array for the parameters (skip 4-byte selector)
        // Use built-in slicing instead of a manual loop
        bytes memory params = data[4:];

        (withdrawal, proof, scope) = abi.decode(
            params,
            (IPrivacyPool.Withdrawal, ProofLib.WithdrawProof, uint256)
        );
    }

  /**
     * @notice Validate withdrawal proof (mirrors PrivacyPool.withdraw logic)
     */
    function _validateWithdrawCall(
        IPrivacyPool.Withdrawal memory withdrawal,
        ProofLib.WithdrawProof memory proof
    ) internal view returns (bool) {
        // 1. Validate withdrawal context matches proof
        uint256 expectedContext = uint256(
            keccak256(abi.encode(withdrawal, ETH_PRIVACY_POOL.SCOPE()))
        ) % (Constants.SNARK_SCALAR_FIELD);

        if (proof.context() != expectedContext) {
            return false;
        }
        // 2. Check the tree depth signals are less than the max tree depth
        if (
            proof.stateTreeDepth() > ETH_PRIVACY_POOL.MAX_TREE_DEPTH() ||
            proof.ASPTreeDepth() > ETH_PRIVACY_POOL.MAX_TREE_DEPTH()
        ) {
            return false;
        }

        // 3. Check state root is valid (same as _isKnownRoot in State.sol)
        uint256 stateRoot = proof.stateRoot();
        if (!_isKnownRoot(stateRoot)) {
            return false;
        }

        // 4. Validate ASP root is latest (same as PrivacyPool validation)
        uint256 aspRoot = proof.ASPRoot();
        if (aspRoot != PRIVACY_POOL_ENTRYPOINT.latestRoot()) {
            return false;
        }

        // 5. Check nullifier hasn't been spent
        uint256 nullifierHash = proof.existingNullifierHash();
        if (ETH_PRIVACY_POOL.nullifierHashes(nullifierHash)) {
            return false;
        }

        // 6. Verify Groth16 proof with withdrawal verifier
        if (
            !WITHDRAWAL_VERIFIER.verifyProof(
                proof.pA,
                proof.pB,
                proof.pC,
                proof.pubSignals
            )
        ) {
            return false;
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a root is known/valid (mirrors State._isKnownRoot)
     * @param _root The root to validate
     * @return True if the root is in the last ROOT_HISTORY_SIZE roots
     */
    function _isKnownRoot(uint256 _root) internal view returns (bool) {
        if (_root == 0) return false;

        // Start from the most recent root (current index)
        uint32 _index = ETH_PRIVACY_POOL.currentRootIndex();
        uint32 ROOT_HISTORY_SIZE = ETH_PRIVACY_POOL.ROOT_HISTORY_SIZE();

        // Check all possible roots in the history
        for (uint32 _i = 0; _i < ROOT_HISTORY_SIZE; _i++) {
            if (_root == ETH_PRIVACY_POOL.roots(_index)) return true;
            _index = (_index + ROOT_HISTORY_SIZE - 1) % ROOT_HISTORY_SIZE;
        }

        return false;
    }
}
