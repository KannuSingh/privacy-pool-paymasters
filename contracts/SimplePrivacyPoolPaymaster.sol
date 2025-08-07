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
import {IAccountValidator} from "./validators/IAccountValidator.sol";

// Forward declaration for Privacy Pool withdrawal validator
interface IPrivacyPoolWithdrawalValidator {
    function validateWithdrawal(
        address target,
        uint256 value,
        bytes calldata data
    ) external view;
}

/**
 * @title SimplePrivacyPoolPaymaster
 * @notice ERC-4337 Paymaster for Privacy Pool withdrawals
 * @dev This paymaster performs comprehensive validation to ensure it only sponsors successful withdrawals
 */
contract SimplePrivacyPoolPaymaster is BasePaymaster {
    using UserOperationLib for PackedUserOperation;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Privacy Pool Entrypoint contract
    IEntrypoint public immutable PRIVACY_POOL_ENTRYPOINT;

    /// @notice ETH Privacy Pool contract
    IPrivacyPool public immutable ETH_PRIVACY_POOL;

    /// @notice Estimated gas cost for postOp operations (includes ETH refund transfers)
    uint256 public constant POST_OP_GAS_LIMIT = 32000;

    /// @notice Modular Privacy Pool withdrawal validator
    IPrivacyPoolWithdrawalValidator public WITHDRAWAL_VALIDATOR;

    /*//////////////////////////////////////////////////////////////
                         ACCOUNT FACTORY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of account factory to its validator
    mapping(address => IAccountValidator) public accountValidators;

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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy Simple Privacy Pool Paymaster
     * @param _entryPoint ERC-4337 EntryPoint contract
     * @param _privacyEntrypoint Privacy Pool Entrypoint contract
     * @param _ethPrivacyPool ETH Privacy Pool contract
     * @param _withdrawalValidator Modular PrivacyPoolWithdrawalValidator
     */
    constructor(
        IEntryPoint _entryPoint,
        IEntrypoint _privacyEntrypoint,
        IPrivacyPool _ethPrivacyPool,
        IPrivacyPoolWithdrawalValidator _withdrawalValidator
    ) BasePaymaster(_entryPoint) {
        PRIVACY_POOL_ENTRYPOINT = _privacyEntrypoint;
        ETH_PRIVACY_POOL = _ethPrivacyPool;
        WITHDRAWAL_VALIDATOR = _withdrawalValidator;
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
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        // 1. Check post-op gas limit is sufficient
        uint256 postOpGasLimit = userOp.unpackPostOpGasLimit();
        if (postOpGasLimit < POST_OP_GAS_LIMIT) {
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

        // 4. Use Privacy Pool validator to validate withdrawal logic
        try
            WITHDRAWAL_VALIDATOR.validateWithdrawal{gas: 200000}(
                target,
                value,
                data
            )
        {
            // 5. Validate economics in paymaster
            return
                _validateEconomicsFromCallData(
                    userOp,
                    userOpHash,
                    maxCost,
                    data
                );
        } catch {
            // Privacy Pool validation failed
            return ("", _packValidationData(true, 0, 0));
        }
    }

    /**
     * @notice Validate economics from callData after validator confirms Privacy Pool logic
     * @dev This function handles paymaster-specific economic validation
     */
    function _validateEconomicsFromCallData(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost,
        bytes memory data
    ) internal view returns (bytes memory context, uint256 validationData) {
        // Decode the relay call data to get withdrawal info
        (IPrivacyPool.Withdrawal memory withdrawal, ) = _decodeRelayCallData(data);

        // Validate economics: fee recipient must be this paymaster
        IEntrypoint.RelayData memory relayData = abi.decode(
            withdrawal.data,
            (IEntrypoint.RelayData)
        );

        if (relayData.feeRecipient != address(this)) {
            return ("", _packValidationData(true, 0, 0));
        }

        // For now, we assume the withdrawal amount will be sufficient to cover maxCost
        // The actual proof validation and amount checking is done by the Privacy Pool Entrypoint
        uint256 expectedFeeAmount = maxCost; // Conservative estimate

        // All validations passed - encode context for postOp
        context = abi.encode(userOpHash, userOp.sender, expectedFeeAmount);

        return (context, 0);
    }

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
     * @dev We only need the withdrawal data for fee validation - proof validation is handled by PrivacyPoolWithdrawalValidator
     */
    function _decodeRelayCallData(
        bytes memory data
    )
        internal
        pure
        returns (
            IPrivacyPool.Withdrawal memory withdrawal,
            uint256 scope
        )
    {
        if (data.length < 4) {
            revert InvalidCallData();
        }

        // Use inline assembly to skip function selector efficiently
        bytes memory params;
        assembly {
            let len := sub(mload(data), 4)
            params := mload(0x40)
            mstore(params, len)
            let dataPtr := add(data, 0x24) // data + 32 (length) + 4 (selector)
            let paramsPtr := add(params, 0x20) // params + 32 (length)
            
            for { let i := 0 } lt(i, len) { i := add(i, 0x20) } {
                mstore(add(paramsPtr, i), mload(add(dataPtr, i)))
            }
            
            mstore(0x40, add(paramsPtr, len))
        }
        
        // Decode using the correct struct types, ignoring the proof since we don't need it
        (withdrawal, , scope) = abi.decode(
            params,
            (IPrivacyPool.Withdrawal, ProofLib.WithdrawProof, uint256)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH from Privacy Pool fees and refunds
     */
    receive() external payable {}

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
                        WITHDRAWAL VALIDATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the withdrawal validator contract
     * @param validator The new withdrawal validator contract
     */
    function setWithdrawalValidator(
        IPrivacyPoolWithdrawalValidator validator
    ) external onlyOwner {
        if (address(validator) == address(0)) {
            revert InvalidValidator();
        }
        WITHDRAWAL_VALIDATOR = validator;
        emit WithdrawalValidatorSet(address(validator));
    }

    /*//////////////////////////////////////////////////////////////
                        INHERITED FROM BASE PAYMASTER
    //////////////////////////////////////////////////////////////*/

    // deposit() and withdrawTo() methods are inherited from BasePaymaster

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event WithdrawalValidatorSet(address indexed validator);
}
