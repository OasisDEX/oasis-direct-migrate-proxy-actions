pragma solidity ^0.5.11;

import "ds-test/test.sol";

import "./OasisDirectMigrateProxyActions.sol";

contract OasisDirectMigrateProxyActionsTest is DSTest {
    OasisDirectMigrateProxyActions actions;

    function setUp() public {
        actions = new OasisDirectMigrateProxyActions();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
