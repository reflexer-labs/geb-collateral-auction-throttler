pragma solidity 0.6.7;

import "ds-test/test.sol";

import "geb/SAFEEngine.sol";
import "geb/LiquidationEngine.sol";
import "./mock/MockTreasury.sol";

import {CollateralAuctionThrottler} from "../CollateralAuctionThrottler.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract CustomSAFEEngine is SAFEEngine {
    uint256 public globalDebt;

    function modifyGlobalDebt(bytes32 parameter, uint data) external {
        globalDebt = data;
    }
}

contract CollateralAuctionThrottlerTest is DSTest {
    Hevm hevm;

    DSToken systemCoin;

    CustomSAFEEngine safeEngine;
    LiquidationEngine liquidationEngine;
    MockTreasury treasury;

    CollateralAuctionThrottler throttler;

    // Throttler vars
    uint256 updateDelay                     = 1 hours;
    uint256 backupUpdateDelay               = 6 hours;
    uint256 baseUpdateCallerReward          = 5E18;
    uint256 maxUpdateCallerReward           = 10E18;
    uint256 perSecondCallerRewardIncrease   = 1000192559420674483977255848; // 100% per hour
    uint256 globalDebtPercentage            = 20;
    address[] surplusHolders;

    address alice   = address(0x1);
    address bob     = address(0x2);
    address charlie = address(0x3);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        surplusHolders.push(alice);
        surplusHolders.push(bob);

        systemCoin        = new DSToken("RAI", "RAI");

        safeEngine        = new CustomSAFEEngine();
        liquidationEngine = new LiquidationEngine(address(safeEngine));
        treasury          = new MockTreasury(address(systemCoin));

        throttler         = new CollateralAuctionThrottler(
          address(safeEngine),
          address(liquidationEngine),
          address(treasury),
          updateDelay,
          backupUpdateDelay,
          baseUpdateCallerReward,
          maxUpdateCallerReward,
          perSecondCallerRewardIncrease,
          globalDebtPercentage,
          surplusHolders
        );
        liquidationEngine.addAuthorization(address(throttler));

        delete(surplusHolders);
    }

    function test_setup() public {

    }
}
