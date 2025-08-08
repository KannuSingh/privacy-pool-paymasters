// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/**
 * @title IAccountValidator
 * @notice Interface for account-specific callData validation
 * @dev Different account implementations (SimpleAccount, Safe, Kernel, etc.) 
 *      have different execute function signatures. This interface allows
 *      the paymaster to support multiple account types by validating
 *      their specific callData format and extracting the target call.
 */
interface IAccountValidator {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidSelector();
    error InvalidCallDataLength();
    error InvalidTarget();
    error InvalidValue();
    error EmptyBatch();
    error MultipleCalls();
    
    /**
     * @notice Validate account callData and extract Privacy Pool call parameters
     * @dev This function should:
     *      1. Validate the callData matches expected account function signatures
     *      2. Ensure only Privacy Pool Entrypoint calls are allowed
     *      3. For batch operations, ensure exactly one Privacy Pool call
     *      4. Extract the target, value, and data for Privacy Pool validation
     * 
     * @param callData The complete callData from UserOperation
     * @return target The target address (must be Privacy Pool Entrypoint)
     * @return value The ETH value (must be 0 for Privacy Pool calls)
     * @return data The calldata for the Privacy Pool call
     * 
     * @custom:security This function should revert if:
     *                  - callData doesn't match expected function signatures
     *                  - target is not Privacy Pool Entrypoint
     *                  - value is not 0
     *                  - batch contains multiple calls
     *                  - batch contains non-Privacy Pool calls
     */
    function validateAndExtract(bytes calldata callData) 
        external 
        view 
        returns (
            address target, 
            uint256 value, 
            bytes memory data
        );
    
    /**
     * @notice Get the account factory that this validator supports
     * @return factory The account factory address
     */
    function supportedFactory() external view returns (address factory);
    
    /**
     * @notice Get human-readable name for this validator
     * @return name The validator name (e.g., "SimpleAccount", "Safe", "Kernel")
     */
    function name() external view returns (string memory name);
}