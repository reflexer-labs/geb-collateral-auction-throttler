pragma solidity ^0.6.7;

import "./MockToken.sol";
import "../../../lib/geb/src/SAFEEngine.sol";
import "../../../lib/geb/src/LiquidationEngine.sol";
import "../mock/MockTreasury.sol";
import {CollateralAuctionThrottlerMock} from "./CollateralAuctionThrottlerMock.sol";

contract CustomSAFEEngine is SAFEEngine {
    function modifyGlobalDebt(bytes32 parameter, uint data) external {
        globalDebt = data;
    }
}

contract Fuzz {

    MockToken systemCoin;

    CustomSAFEEngine safeEngine;
    LiquidationEngine liquidationEngine;
    MockTreasury treasury;

    CollateralAuctionThrottlerMock throttler;

    // Throttler vars
    uint256 updateDelay                     = 1 hours;
    uint256 backupUpdateDelay               = 6 hours;
    uint256 baseUpdateCallerReward          = 5E18;
    uint256 maxUpdateCallerReward           = 10E18;
    uint256 maxRewardIncreaseDelay          = 6 hours;
    uint256 perSecondCallerRewardIncrease   = 1000192559420674483977255848; // 100% per hour
    uint256 globalDebtPercentage            = 20;
    address[] surplusHolders;

    address alice   = address(0xabc);
    address bob     = address(0xcde);

    constructor() public {
        surplusHolders.push(alice);
        surplusHolders.push(bob);

        systemCoin        = new MockToken("RAI", "RAI");
        safeEngine        = new CustomSAFEEngine();
        liquidationEngine = new LiquidationEngine(address(safeEngine));
        treasury          = new MockTreasury(address(systemCoin));

        systemCoin.mint(address(treasury), 1000E18);

        throttler         = new CollateralAuctionThrottlerMock(
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
        throttler.modifyParameters("maxRewardIncreaseDelay", 6 hours); // note: test this witn unlimited and lenghty maxDelay

        treasury.setPerBlockAllowance(address(throttler), maxUpdateCallerReward * 10 ** 27);
        treasury.setTotalAllowance(address(throttler), uint(-1));

        liquidationEngine.addAuthorization(address(throttler));

        delete(surplusHolders);
    }

    function fuzzGlobalDebt(uint globalDebt) public {
        safeEngine.modifyGlobalDebt("globalDebt", globalDebt);
    }

    // function fuzzSurplus
    // function fuzzParams

    function fuzzRecompute() public {
        throttler.recomputeOnAuctionSystemCoinLimit(address(0xfab));
        assert(throttler.lastUpdateTime() == now);
        assert(liquidationEngine.onAuctionSystemCoinLimit() == safeEngine.globalDebt() * throttler.globalDebtPercentage() / 100);

        // increased precision allows for globalDebt up to ( at 3.14), uint(-1) test now breaks
    }

    function fuzzBackupRecompute() public {
        throttler.backupRecomputeOnAuctionSystemCoinLimit();
        assert(throttler.lastUpdateTime() == now);
        assert(liquidationEngine.onAuctionSystemCoinLimit() == uint(-1));
    }    
}