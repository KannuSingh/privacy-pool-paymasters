// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Karandeep Singh (https://github.com/KannuSingh)
pragma solidity 0.8.28;

import {IAccountValidator} from "../interfaces/IAccountValidator.sol";

/**
 * @title SimpleAccountValidator
 * @notice Validator for SimpleAccount (ERC-4337 reference implementation)
 * @dev Validates callData for SimpleAccount.execute() and SimpleAccount.executeBatch()
 *      Ensures only Privacy Pool Entrypoint calls are allowed.
 */
contract SimpleAccountValidator is IAccountValidator {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice SimpleAccount factory address
    address public immutable SIMPLE_ACCOUNT_FACTORY;
    
    /// @notice Privacy Pool Entrypoint address
    address public immutable PRIVACY_POOL_ENTRYPOINT;
    
    /// @notice SimpleAccount.execute() function selector
    bytes4 public constant EXECUTE_SELECTOR = 0xb61d27f6;
    
    /// @notice SimpleAccount.executeBatch() function selector  
    bytes4 public constant EXECUTE_BATCH_SELECTOR = 0x47e1da2a;
    
    
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deploy SimpleAccountValidator
     * @param _factory SimpleAccount factory address
     * @param _entrypoint Privacy Pool Entrypoint address
     */
    constructor(address _factory, address _entrypoint) {
        SIMPLE_ACCOUNT_FACTORY = _factory;
        PRIVACY_POOL_ENTRYPOINT = _entrypoint;
    }
    
    /*//////////////////////////////////////////////////////////////
                         VALIDATION INTERFACE
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate SimpleAccount callData and extract Privacy Pool call
     * @dev Supports both execute() and executeBatch() with restrictions:
     *      - execute(): target must be Privacy Pool Entrypoint, value must be 0
     *      - executeBatch(): must contain exactly 1 call to Privacy Pool Entrypoint
     */
    function validateAndExtract(bytes calldata callData) 
        external 
        view 
        override
        returns (
            address target, 
            uint256 value, 
            bytes memory data
        ) 
    {
        if (callData.length < 4) {
            revert InvalidCallDataLength();
        }
        
        bytes4 selector = bytes4(callData[:4]);
        
        if (selector == EXECUTE_SELECTOR) {
            return _validateExecute(callData);
        } else if (selector == EXECUTE_BATCH_SELECTOR) {
            return _validateExecuteBatch(callData);
        } else {
            revert InvalidSelector();
        }
    }
    
    /**
     * @notice Get the SimpleAccount factory address
     */
    function supportedFactory() external view override returns (address) {
        return SIMPLE_ACCOUNT_FACTORY;
    }
    
    /**
     * @notice Get validator name
     */
    function name() external pure override returns (string memory) {
        return "SimpleAccount";
    }
    
    /*//////////////////////////////////////////////////////////////
                         INTERNAL VALIDATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate SimpleAccount.execute(address target, uint256 value, bytes calldata data)
     */
    function _validateExecute(bytes calldata callData) 
        internal 
        view 
        returns (address target, uint256 value, bytes memory data) 
    {
        if (callData.length < 4) {
            revert InvalidCallDataLength();
        }
        
        // Decode execute parameters
        (target, value, data) = abi.decode(callData[4:], (address, uint256, bytes));
        
        // Validate target is Privacy Pool Entrypoint
        if (target != PRIVACY_POOL_ENTRYPOINT) {
            revert InvalidTarget();
        }
        
        // Validate no ETH value transfer
        if (value != 0) {
            revert InvalidValue();
        }
        
        return (target, value, data);
    }
    
    /**
     * @notice Validate SimpleAccount.executeBatch(address[] targets, uint256[] values, bytes[] calldatas)
     * @dev Ensures batch contains exactly one Privacy Pool Entrypoint call
     */
    function _validateExecuteBatch(bytes calldata callData) 
        internal 
        view 
        returns (address target, uint256 value, bytes memory data) 
    {
        if (callData.length < 4) {
            revert InvalidCallDataLength();
        }
        
        // Decode executeBatch parameters
        (address[] memory targets, uint256[] memory values, bytes[] memory datas) = 
            abi.decode(callData[4:], (address[], uint256[], bytes[]));
        
        // Validate arrays have same length and exactly 1 element
        if (targets.length == 0 || values.length == 0 || datas.length == 0) {
            revert EmptyBatch();
        }
        
        if (targets.length != 1 || values.length != 1 || datas.length != 1) {
            revert MultipleCalls();
        }
        
        // Extract the single call
        target = targets[0];
        value = values[0];
        data = datas[0];
        
        // Validate target is Privacy Pool Entrypoint
        if (target != PRIVACY_POOL_ENTRYPOINT) {
            revert InvalidTarget();
        }
        
        // Validate no ETH value transfer
        if (value != 0) {
            revert InvalidValue();
        }
        
        return (target, value, data);
    }
}