// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IStakeManager} from "@account-abstraction/contracts/interfaces/IStakeManager.sol";
import {INonceManager} from "@account-abstraction/contracts/interfaces/INonceManager.sol";
import {ISenderCreator} from "@account-abstraction/contracts/interfaces/ISenderCreator.sol";
import {IERC165} from "@oz/utils/introspection/IERC165.sol";

/**
 * @title MockEntryPoint
 * @notice Minimal mock of ERC-4337 EntryPoint for testing
 */
contract MockEntryPoint is IEntryPoint, IERC165 {
    mapping(address => uint256) public deposits;
    
    function depositTo(address account) public payable {
        deposits[account] += msg.value;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return deposits[account];
    }
    
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) public {
        deposits[msg.sender] -= withdrawAmount;
        withdrawAddress.transfer(withdrawAmount);
    }
    
    // Minimal implementations for interface compliance
    function handleOps(PackedUserOperation[] calldata, address payable) external pure {
        revert("Not implemented");
    }
    
    function handleAggregatedOps(
        UserOpsPerAggregator[] calldata,
        address payable
    ) external pure {
        revert("Not implemented");
    }
    
    function getUserOpHash(PackedUserOperation calldata) external pure returns (bytes32) {
        return bytes32(0);
    }
    
    // IStakeManager implementations
    function addStake(uint32) external payable {
        revert("Not implemented");
    }
    
    function unlockStake() external pure {
        revert("Not implemented");
    }
    
    function withdrawStake(address payable) external pure {
        revert("Not implemented");
    }
    
    function getDepositInfo(address account) external view returns (DepositInfo memory) {
        return DepositInfo({
            deposit: deposits[account],
            staked: false,
            stake: 0,
            unstakeDelaySec: 0,
            withdrawTime: 0
        });
    }
    
    // INonceManager implementations
    function getNonce(address sender, uint192 key) external pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(sender, key)));
    }
    
    function incrementNonce(uint192) external pure {
        revert("Not implemented");
    }
    
    // IEntryPoint specific implementations
    function delegateAndRevert(address, bytes calldata) external pure {
        revert("Not implemented");
    }
    
    function getSenderAddress(bytes memory) external pure {
        revert("Not implemented");
    }
    
    function senderCreator() external pure returns (ISenderCreator) {
        revert("Not implemented");
    }
    
    // IERC165 implementation
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return 
            interfaceId == type(IEntryPoint).interfaceId ||
            interfaceId == type(IStakeManager).interfaceId ||
            interfaceId == type(INonceManager).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
    
    receive() external payable {}
}