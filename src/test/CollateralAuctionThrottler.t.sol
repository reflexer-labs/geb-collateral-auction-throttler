pragma solidity 0.6.7;

import "ds-test/test.sol";

import "geb/SAFEEngine.sol";
import "geb/LiquidationEngine.sol";

import "../CollateralAuctionThrottler.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}
contract CollateralAuctionThrottlerTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    LiquidationEngine liquidationEngine;

    CollateralAuctionThrottler throttler;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine        = new SAFEEngine();
        liquidationEngine = new LiquidationEngine(address(safeEngine));

        throttler         = new CollateralAuctionThrottler();
    }
}
