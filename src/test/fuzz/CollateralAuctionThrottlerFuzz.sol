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

    function modifyCoinBalance(address guy, uint balance) external {
        coinBalance[guy] = balance;
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
    uint256 backupUpdateDelay               = 8 hours;
    uint256 baseUpdateCallerReward          = 5E18;
    uint256 maxUpdateCallerReward           = 10E18;
    uint256 perSecondCallerRewardIncrease   = 1000192559420674483977255848; // 100% per hour
    uint256 globalDebtPercentage            = 20;
    address[] surplusHolders;

    address surplusHolder   = address(0xabc);
    address bob     = address(0xcde);

    constructor() public {
        surplusHolders.push(surplusHolder);
        surplusHolders.push(bob);

        systemCoin        = new MockToken("RAI", "RAI");
        safeEngine        = new CustomSAFEEngine();
        liquidationEngine = new LiquidationEngine(address(safeEngine));
        treasury          = new MockTreasury(address(systemCoin));

        systemCoin.mint(address(treasury), uint(-1)); // unlimited funds for treasury

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

        treasury.setPerBlockAllowance(address(throttler), uint(-1));
        treasury.setTotalAllowance(address(throttler), uint(-1));

        liquidationEngine.addAuthorization(address(throttler));
    }

    function fuzzGlobalDebt(uint globalDebt) public {
        safeEngine.modifyGlobalDebt("globalDebt", globalDebt);
    }
    
    function FuzzSurplus(uint surplus) public {
        safeEngine.modifyCoinBalance(surplusHolder, surplus);
    }

    function fuzzParams(uint _updateDelay, uint _backupUpdateDelay, uint _globalDebtPercentage) public {
        try throttler.modifyParameters("updateDelay", _updateDelay % 4 weeks) {} catch {}
        try throttler.modifyParameters("backupUpdateDelay", _backupUpdateDelay % 12 weeks) {} catch {}
        try throttler.modifyParameters("globalDebtPercentage", _globalDebtPercentage % 100) {} catch {}
    }

    function fuzzRewardParams(
        uint _baseUpdateCallerReward,
        uint _maxUpdateCallerReward,
        uint _perSecondCallerRewardIncrease,
        uint _maxRewardIncreaseDelay
    ) public {
        try throttler.modifyParameters("baseUpdateCallerReward", _baseUpdateCallerReward % 10000E18) {} catch {}
        try throttler.modifyParameters("maxUpdateCallerReward", _maxUpdateCallerReward % 20000E18) {} catch {}
        try throttler.modifyParameters("perSecondCallerRewardIncrease", _perSecondCallerRewardIncrease) {} catch {}
        try throttler.modifyParameters("maxRewardIncreaseDelay", _maxRewardIncreaseDelay) {} catch {}
    }

    function fuzzRecompute() public {
        throttler.recomputeOnAuctionSystemCoinLimit(address(0xfab));
        assert(systemCoin.balanceOf(address(0xfab)) >= throttler.baseUpdateCallerReward());
        assert(throttler.lastUpdateTime() == now);
        assert(liquidationEngine.onAuctionSystemCoinLimit() == (safeEngine.globalDebt() - safeEngine.coinBalance(surplusHolder)) * throttler.globalDebtPercentage() / 100); // overflows for values close to max_uint, should not be an issue (10**30 * RAD debt)
    }

    function fuzzBackupRecompute() public {
        throttler.backupRecomputeOnAuctionSystemCoinLimit();
        assert(throttler.lastUpdateTime() == now);
        assert(liquidationEngine.onAuctionSystemCoinLimit() == uint(-1));
    }    
}