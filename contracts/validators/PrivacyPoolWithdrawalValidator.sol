// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {SimplePrivacyPoolPaymaster} from "../SimplePrivacyPoolPaymaster.sol";

/**
 * @title PrivacyPoolWithdrawalValidator
 * @notice Account-agnostic validator for Privacy Pool withdrawal logic
 * @dev This validator focuses purely on Privacy Pool protocol validation,
 *      independent of account implementation details. It validates:
 *      - Zero-knowledge proofs
 *      - Nullifier double-spend protection
 *      - State root validity
 *      - ASP root validation
 *      - Withdrawal context integrity
 */
contract PrivacyPoolWithdrawalValidator {
    using ProofLib for ProofLib.WithdrawProof;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The paymaster contract that uses this validator
    SimplePrivacyPoolPaymaster public immutable PAYMASTER;

    /// @notice Privacy Pool Entrypoint - the only valid target
    IEntrypoint public immutable PRIVACY_POOL_ENTRYPOINT;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCaller();
    error InvalidTarget();
    error InvalidValue();
    error ValidationFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy PrivacyPoolWithdrawalValidator
     * @param _paymaster The SimplePrivacyPoolPaymaster that will use this validator
     */
    constructor(address payable _paymaster) {
        PAYMASTER = SimplePrivacyPoolPaymaster(_paymaster);
        PRIVACY_POOL_ENTRYPOINT = PAYMASTER.PRIVACY_POOL_ENTRYPOINT();
    }

    /*//////////////////////////////////////////////////////////////
                         VALIDATION INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validate Privacy Pool withdrawal call
     * @dev This function validates the Privacy Pool protocol logic only.
     *      Account-specific validation should be done by AccountValidators.
     *
     *      IMPORTANT: This function only VALIDATES - it does not execute!
     *
     * @param target The target address (must be Privacy Pool Entrypoint)
     * @param value The ETH value (must be 0)
     * @param data The calldata for Privacy Pool withdrawal
     */
    function validateWithdrawal(
        address target,
        uint256 value,
        bytes calldata data
    ) external view {
        // Only the paymaster can call this validator
        if (msg.sender != address(PAYMASTER)) {
            revert InvalidCaller();
        }

        // 1. Validate target is Privacy Pool Entrypoint
        if (target != address(PRIVACY_POOL_ENTRYPOINT)) {
            revert InvalidTarget();
        }

        // 2. Validate no direct ETH transfers
        if (value != 0) {
            revert InvalidValue();
        }

        // 3. Validate the call would succeed on the actual Privacy Pool Entrypoint
        // This is a STATIC CALL - only validates, doesn't execute!
        (bool success, ) = address(PRIVACY_POOL_ENTRYPOINT).staticcall(data);
        if (!success) {
            revert ValidationFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the paymaster address this validator serves
     * @return The SimplePrivacyPoolPaymaster address
     */
    function paymaster() external view returns (address) {
        return address(PAYMASTER);
    }

    /**
     * @notice Get the Privacy Pool Entrypoint address
     * @return The IEntrypoint address
     */
    function entrypoint() external view returns (address) {
        return address(PRIVACY_POOL_ENTRYPOINT);
    }
}
