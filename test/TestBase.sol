// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

/**
 * @title TestBase
 * @notice Base contract for all tests with common utilities and constants
 */
contract TestBase is Test {
    /*//////////////////////////////////////////////////////////////
                              TEST CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // ERC-4337 constants
    address constant ENTRYPOINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    // Test addresses
    address constant ALICE = address(0x100);
    address constant BOB = address(0x200);
    address constant CHARLIE = address(0x300);
    address constant DAVE = address(0x400);

    // Mock addresses for Privacy Pool components
    address constant MOCK_PRIVACY_ENTRYPOINT = address(0x1000);
    address constant MOCK_ETH_PRIVACY_POOL = address(0x2000);
    address constant MOCK_WITHDRAWAL_VERIFIER = address(0x3000);
    address constant MOCK_SIMPLE_ACCOUNT_FACTORY = address(0x4000);

    // Gas constants
    uint256 constant POST_OP_GAS_LIMIT = 32000;
    uint256 constant VALIDATION_GAS_LIMIT = 200000;
    // Snark Scalar Field
    uint256 public constant SNARK_SCALAR_FIELD =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    /*//////////////////////////////////////////////////////////////
                              TEST UTILITIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set up test environment
     */
    function setUp() public virtual {
        // Label test addresses for better trace output
        vm.label(ALICE, "Alice");
        vm.label(BOB, "Bob");
        vm.label(CHARLIE, "Charlie");
        vm.label(DAVE, "Dave");

        vm.label(ENTRYPOINT_V7, "EntryPoint");
        vm.label(MOCK_PRIVACY_ENTRYPOINT, "MockPrivacyEntrypoint");
        vm.label(MOCK_ETH_PRIVACY_POOL, "MockEthPrivacyPool");
        vm.label(MOCK_WITHDRAWAL_VERIFIER, "MockWithdrawalVerifier");
        vm.label(MOCK_SIMPLE_ACCOUNT_FACTORY, "MockSimpleAccountFactory");
    }

    /**
     * @notice Create test initCode for fresh accounts
     * @param factory The account factory address
     * @param salt The salt for account creation
     */
    function createInitCode(
        address factory,
        uint256 salt
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(factory, abi.encode(salt));
    }

    /**
     * @notice Create SimpleAccount.execute() calldata
     * @param target The target contract
     * @param value ETH value to send
     * @param data The calldata
     */
    function createExecuteCalldata(
        address target,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(0xb61d27f6, target, value, data);
    }

    /**
     * @notice Create SimpleAccount.executeBatch() calldata
     * @param targets Array of target contracts
     * @param values Array of ETH values
     * @param datas Array of calldatas
     */
    function createExecuteBatchCalldata(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(0x47e1da2a, targets, values, datas);
    }

    /**
     * @notice Helper to expect generic revert
     */
    function expectRevert() internal {
        vm.expectRevert();
    }

    /**
     * @notice Helper to expect specific revert
     */
    function expectRevert(bytes4 selector) internal {
        vm.expectRevert(selector);
    }

    /**
     * @notice Helper to expect specific revert with data
     */
    function expectRevert(bytes memory revertData) internal {
        vm.expectRevert(revertData);
    }
}
