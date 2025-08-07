// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";

/**
 * @title MockPrivacyPoolComponents
 * @notice Simple mock implementations for testing
 */

contract MockPrivacyPool {
    address public constant ASSET = address(0);
    uint256 public constant SCOPE = 1;
    address public immutable WITHDRAWAL_VERIFIER;
    uint32 public constant MAX_TREE_DEPTH = 20;
    uint32 public constant ROOT_HISTORY_SIZE = 64;
    
    uint32 public currentRootIndex;
    mapping(uint32 => uint256) public roots;
    mapping(uint256 => bool) public nullifierHashes;
    
    constructor(address _verifier) {
        WITHDRAWAL_VERIFIER = _verifier;
        // Initialize with a mock root
        roots[0] = 1234567890;
        currentRootIndex = 0;
    }
    
    function setNullifierUsed(uint256 nullifier) external {
        nullifierHashes[nullifier] = true;
    }
    
    function setRoot(uint32 index, uint256 root) external {
        roots[index] = root;
        currentRootIndex = index;
    }
}

contract MockEntrypoint {
    address public immutable ETH_PRIVACY_POOL;
    uint256 private _latestRoot = 9876543210;
    bool private _shouldRelaySucceed = true;
    
    struct PoolAssetConfig {
        address pool;
        uint256 minimumDepositAmount;
        uint256 vettingFeeBPS;
        uint256 maxRelayFeeBPS;
    }
    
    mapping(IERC20 => PoolAssetConfig) private _assetConfigs;
    mapping(uint256 => address) private _scopeToPools;
    
    constructor(address _ethPrivacyPool) {
        ETH_PRIVACY_POOL = _ethPrivacyPool;
        
        // Set up default asset config
        _assetConfigs[IERC20(address(0))] = PoolAssetConfig({
            pool: _ethPrivacyPool,
            minimumDepositAmount: 0.1 ether,
            vettingFeeBPS: 100, // 1%
            maxRelayFeeBPS: 1000 // 10%
        });
        
        _scopeToPools[1] = _ethPrivacyPool;
    }
    
    function latestRoot() external view returns (uint256) {
        return _latestRoot;
    }
    
    function setLatestRoot(uint256 root) external {
        _latestRoot = root;
    }
    
    function setShouldRelaySucceed(bool _should) external {
        _shouldRelaySucceed = _should;
    }
    
    function scopeToPool(uint256 scope) external view returns (address) {
        return _scopeToPools[scope];
    }
    
    function assetConfig(IERC20 asset) external view returns (
        address pool,
        uint256 minimumDepositAmount,
        uint256 vettingFeeBPS,
        uint256 maxRelayFeeBPS
    ) {
        PoolAssetConfig memory config = _assetConfigs[asset];
        return (config.pool, config.minimumDepositAmount, config.vettingFeeBPS, config.maxRelayFeeBPS);
    }
    
    /**
     * @notice Mock relay function for testing - validates withdrawal parameters
     * @param _withdrawal The withdrawal struct
     * @param _scope The pool scope
     */
    function relay(
        IPrivacyPool.Withdrawal calldata _withdrawal,
        ProofLib.WithdrawProof calldata /* _proof */,
        uint256 _scope
    ) external view {
        // Check if relay should succeed
        if (!_shouldRelaySucceed) {
            revert("Mock relay failure");
        }
        
        // Basic validation for mock - check if withdrawal is properly formatted
        require(_withdrawal.processooor != address(0), "Invalid processooor");
        // Relaxed validation: allow empty data for tests
        require(_scope > 0, "Invalid scope");
        
        // In a real implementation, this would validate the ZK proof, check nullifiers, etc.
        // For our mock, we just do basic parameter validation
    }
}

contract MockVerifier {
    bool private _shouldSucceed = true;
    
    function setShouldSucceed(bool succeed) external {
        _shouldSucceed = succeed;
    }
    
    function verifyProof(
        uint256[2] memory,
        uint256[2][2] memory,
        uint256[2] memory,
        uint256[] memory
    ) external view returns (bool) {
        return _shouldSucceed;
    }
}