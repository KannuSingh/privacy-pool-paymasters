// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";

/**
 * @title MockSimplePrivacyPoolPaymaster
 * @notice Mock paymaster for testing validators
 */
contract MockSimplePrivacyPoolPaymaster {
    using ProofLib for ProofLib.WithdrawProof;
    
    IEntrypoint public immutable PRIVACY_POOL_ENTRYPOINT;
    
    bool public shouldValidateRelay;
    bool public shouldValidateWithdraw;
    
    constructor(address _privacyEntrypoint) {
        PRIVACY_POOL_ENTRYPOINT = IEntrypoint(_privacyEntrypoint);
        shouldValidateRelay = true;
        shouldValidateWithdraw = true;
    }
    
    function setShouldValidateRelay(bool _should) external {
        shouldValidateRelay = _should;
    }
    
    function setShouldValidateWithdraw(bool _should) external {
        shouldValidateWithdraw = _should;
    }
    
    function validateRelayCall(
        IPrivacyPool.Withdrawal memory /* withdrawal */,
        ProofLib.WithdrawProof memory /* proof */,
        uint256 /* scope */
    ) external view returns (bool) {
        return shouldValidateRelay;
    }
    
    function validateWithdrawCall(
        IPrivacyPool.Withdrawal memory /* withdrawal */,
        ProofLib.WithdrawProof memory /* proof */
    ) external view returns (bool) {
        return shouldValidateWithdraw;
    }
}