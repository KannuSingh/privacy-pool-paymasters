// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {TestBase} from "../TestBase.sol";
import {SimpleAccountValidator} from "../../contracts/validators/SimpleAccountValidator.sol";

/**
 * @title SimpleAccountValidatorTest
 * @notice Unit tests for SimpleAccountValidator
 */
contract SimpleAccountValidatorTest is TestBase {
    SimpleAccountValidator validator;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public override {
        super.setUp();
        
        validator = new SimpleAccountValidator(
            MOCK_SIMPLE_ACCOUNT_FACTORY,
            MOCK_PRIVACY_ENTRYPOINT
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public view {
        assertEq(validator.SIMPLE_ACCOUNT_FACTORY(), MOCK_SIMPLE_ACCOUNT_FACTORY);
        assertEq(validator.PRIVACY_POOL_ENTRYPOINT(), MOCK_PRIVACY_ENTRYPOINT);
        assertEq(validator.supportedFactory(), MOCK_SIMPLE_ACCOUNT_FACTORY);
        assertEq(validator.name(), "SimpleAccount");
    }
    
    /*//////////////////////////////////////////////////////////////
                         EXECUTE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ValidateAndExtract_Execute_Success() public view {
        bytes memory mockData = "test data";
        bytes memory callData = createExecuteCalldata(MOCK_PRIVACY_ENTRYPOINT, 0, mockData);
        
        (address target, uint256 value, bytes memory data) = validator.validateAndExtract(callData);
        
        assertEq(target, MOCK_PRIVACY_ENTRYPOINT);
        assertEq(value, 0);
        assertEq(data, mockData);
    }
    
    function test_ValidateAndExtract_Execute_InvalidTarget() public {
        bytes memory callData = createExecuteCalldata(ALICE, 0, "test data");
        
        expectRevert(SimpleAccountValidator.InvalidTarget.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_Execute_InvalidValue() public {
        bytes memory callData = createExecuteCalldata(MOCK_PRIVACY_ENTRYPOINT, 1 ether, "test data");
        
        expectRevert(SimpleAccountValidator.InvalidValue.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_Execute_InvalidCallDataLength() public {
        bytes memory callData = hex"b61d27f6"; // Just selector, no parameters
        
        expectRevert();
        validator.validateAndExtract(callData);
    }
    
    /*//////////////////////////////////////////////////////////////
                      EXECUTE BATCH VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ValidateAndExtract_ExecuteBatch_Success() public view {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        
        targets[0] = MOCK_PRIVACY_ENTRYPOINT;
        values[0] = 0;
        datas[0] = "test data";
        
        bytes memory callData = createExecuteBatchCalldata(targets, values, datas);
        
        (address target, uint256 value, bytes memory data) = validator.validateAndExtract(callData);
        
        assertEq(target, MOCK_PRIVACY_ENTRYPOINT);
        assertEq(value, 0);
        assertEq(data, datas[0]);
    }
    
    function test_ValidateAndExtract_ExecuteBatch_MultipleCalls() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        
        targets[0] = MOCK_PRIVACY_ENTRYPOINT;
        targets[1] = ALICE;
        values[0] = 0;
        values[1] = 0;
        datas[0] = "test data 1";
        datas[1] = "test data 2";
        
        bytes memory callData = createExecuteBatchCalldata(targets, values, datas);
        
        expectRevert(SimpleAccountValidator.MultipleCalls.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_ExecuteBatch_EmptyBatch() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory datas = new bytes[](0);
        
        bytes memory callData = createExecuteBatchCalldata(targets, values, datas);
        
        expectRevert(SimpleAccountValidator.EmptyBatch.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_ExecuteBatch_InvalidTarget() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        
        targets[0] = ALICE; // Not privacy pool entrypoint
        values[0] = 0;
        datas[0] = "test data";
        
        bytes memory callData = createExecuteBatchCalldata(targets, values, datas);
        
        expectRevert(SimpleAccountValidator.InvalidTarget.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_ExecuteBatch_InvalidValue() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        
        targets[0] = MOCK_PRIVACY_ENTRYPOINT;
        values[0] = 1 ether; // Non-zero value
        datas[0] = "test data";
        
        bytes memory callData = createExecuteBatchCalldata(targets, values, datas);
        
        expectRevert(SimpleAccountValidator.InvalidValue.selector);
        validator.validateAndExtract(callData);
    }
    
    /*//////////////////////////////////////////////////////////////
                          INVALID SELECTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ValidateAndExtract_InvalidSelector() public {
        bytes memory callData = abi.encodeWithSelector(0x12345678, ALICE, 0, "test");
        
        expectRevert(SimpleAccountValidator.InvalidSelector.selector);
        validator.validateAndExtract(callData);
    }
    
    function test_ValidateAndExtract_InvalidCallDataLengthTooShort() public {
        bytes memory callData = hex"1234"; // Valid hex but too short
        
        expectRevert(SimpleAccountValidator.InvalidCallDataLength.selector);
        validator.validateAndExtract(callData);
    }
    
    /*//////////////////////////////////////////////////////////////
                           INTERFACE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SupportedFactory() public view {
        assertEq(validator.supportedFactory(), MOCK_SIMPLE_ACCOUNT_FACTORY);
    }
    
    function test_Name() public view {
        assertEq(validator.name(), "SimpleAccount");
    }
    
    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_ValidateAndExtract_Execute_ValidData(bytes memory data) public view {
        bytes memory callData = createExecuteCalldata(MOCK_PRIVACY_ENTRYPOINT, 0, data);
        
        (address target, uint256 value, bytes memory returnedData) = validator.validateAndExtract(callData);
        
        assertEq(target, MOCK_PRIVACY_ENTRYPOINT);
        assertEq(value, 0);
        assertEq(returnedData, data);
    }
    
    function testFuzz_ValidateAndExtract_Execute_InvalidTarget(address invalidTarget) public {
        vm.assume(invalidTarget != MOCK_PRIVACY_ENTRYPOINT);
        
        bytes memory callData = createExecuteCalldata(invalidTarget, 0, "test");
        
        expectRevert(SimpleAccountValidator.InvalidTarget.selector);
        validator.validateAndExtract(callData);
    }
    
    function testFuzz_ValidateAndExtract_Execute_InvalidValue(uint256 invalidValue) public {
        vm.assume(invalidValue != 0);
        
        bytes memory callData = createExecuteCalldata(MOCK_PRIVACY_ENTRYPOINT, invalidValue, "test");
        
        expectRevert(SimpleAccountValidator.InvalidValue.selector);
        validator.validateAndExtract(callData);
    }
}