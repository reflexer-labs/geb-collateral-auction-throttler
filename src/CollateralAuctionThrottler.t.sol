pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebCollateralAuctionThrottler.sol";

contract GebCollateralAuctionThrottlerTest is DSTest {
    GebCollateralAuctionThrottler throttler;

    function setUp() public {
        throttler = new GebCollateralAuctionThrottler();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
