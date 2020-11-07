pragma solidity ^0.6.7;

import "ds-list/list.sol";

abstract contract LiquidationEngineLike {
    function modifyParameters(bytes32, uint256) virtual external;
}
abstract contract SAFEEngineLike {
    function globalDebt() virtual public view returns (uint256);
    function coinBalance(address) virtual public view returns (uint256);
}
abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual external view returns (uint, uint);
    function systemCoin() virtual external view returns (address);
    function pullFunds(address, address, uint) virtual external;
}

contract CollateralAuctionThrottler {
  using LinkedList for LinkedList.List;

  // --- Auth ---
  mapping (address => uint) public authorizedAccounts;
  /**
   * @notice Add auth to an account
   * @param account Account to add auth to
   */
  function addAuthorization(address account) external isAuthorized {
      authorizedAccounts[account] = 1;
      emit AddAuthorization(account);
  }
  /**
   * @notice Remove auth from an account
   * @param account Account to remove auth from
   */
  function removeAuthorization(address account) external isAuthorized {
      authorizedAccounts[account] = 0;
      emit RemoveAuthorization(account);
  }
  /**
  * @notice Checks whether msg.sender can call an authed function
  **/
  modifier isAuthorized {
      require(authorizedAccounts[msg.sender] == 1, "CollateralAuctionThrottler/account-not-authorized");
      _;
  }

  // Number of surplus holders ever added
  uint256 public surplusHolderNonce;
  // Delay between updates after which the reward starts to increase
  uint256 public updateDelay;
  // Delay since the last update time after which backupLimitRecompute can be called
  uint256 public backupUpdateDelay;
  // Starting reward for the feeReceiver
  uint256 public baseUpdateCallerReward;          // [wad]
  // Max possible reward for the feeReceiver
  uint256 public maxUpdateCallerReward;           // [wad]
  // Max delay taken into consideration when calculating the adjusted reward
  uint256 public maxRewardIncreaseDelay;
  // Rate applied to baseUpdateCallerReward every extra second passed beyond updateDelay seconds since the last update call
  uint256 public perSecondCallerRewardIncrease;   // [ray]
  // Percentage of global debt taken into account in order to set LiquidationEngine.onAuctionSystemCoinLimit
  uint256 public globalDebtPercentage;            // [hundred]
  // ID of the latest surplus holder
  uint256 public latestSurplusHolder;
  // Last timestamp when the median was updated
  uint256 public lastUpdateTime;                  // [unix timestamp]

  // Whether an address is already used for a surplus holder
  mapping (address => uint256) public usedSurplusHolders;
  // ID => address for surplus holders
  mapping (uint256 => address) public surplusHolderAccounts;

  LiquidationEngineLike    public liquidationEngine;
  SAFEEngineLike           public safeEngine;
  StabilityFeeTreasuryLike public treasury;

  // List of surplus holders
  LinkedList.List internal surplusHolders;

  // --- Events ---
  event ModifyParameters(bytes32 parameter, address addr);
  event ModifyParameters(bytes32 parameter, uint256 data);
  event ModifyParameters(uint256 position, address addr);
  event AddSurplusHolder(uint surplusHolderNonce, uint latestSurplusHolder, address surplusHolder);
  event ModifySurplusHolder(uint surplusHolderNonce, uint latestSurplusHolder, address surplusHolder);
  event RewardCaller(address feeReceiver, uint256 amount);
  event FailRewardCaller(bytes revertReason, address finalFeeReceiver, uint256 reward);
  event AddAuthorization(address account);
  event RemoveAuthorization(address account);

  constructor(
    address safeEngine_,
    address liquidationEngine_,
    address treasury_,
    uint256 updateDelay_,
    uint256 backupUpdateDelay_,
    uint256 baseUpdateCallerReward_,
    uint256 maxUpdateCallerReward_,
    uint256 perSecondCallerRewardIncrease_,
    uint256 globalDebtPercentage_
  ) public {
      require(safeEngine_ != address(0), "CollateralAuctionThrottler/null-safe-engine");
      require(liquidationEngine_ != address(0), "CollateralAuctionThrottler/null-liquidation-engine");
      require(maxUpdateCallerReward_ > baseUpdateCallerReward_, "CollateralAuctionThrottler/invalid-max-reward");
      require(perSecondCallerRewardIncrease_ >= RAY, "CollateralAuctionThrottler/invalid-reward-increase");
      require(updateDelay_ > 0, "CollateralAuctionThrottler/null-update-delay");
      require(backupUpdateDelay_ > updateDelay_, "CollateralAuctionThrottler/invalid-backup-update-delay");
      require(both(globalDebtPercentage_ > 0, globalDebtPercentage_ <= 100), "CollateralAuctionThrottler/invalid-global-debt-percentage");
      authorizedAccounts[msg.sender] = 1;
      treasury                       = StabilityFeeTreasuryLike(treasury_);
      safeEngine                     = SAFEEngineLike(safeEngine_);
      liquidationEngine              = LiquidationEngineLike(liquidationEngine_);
      baseUpdateCallerReward         = baseUpdateCallerReward_;
      maxUpdateCallerReward          = maxUpdateCallerReward_;
      perSecondCallerRewardIncrease  = perSecondCallerRewardIncrease_;
      updateDelay                    = updateDelay_;
      backupUpdateDelay              = backupUpdateDelay_;
      globalDebtPercentage           = globalDebtPercentage_;
      maxRewardIncreaseDelay         = uint(-1);

      emit AddAuthorization(msg.sender);
      emit ModifyParameters(bytes32("treasury"), treasury_);
      emit ModifyParameters(bytes32("safeEngine"), safeEngine_);
      emit ModifyParameters(bytes32("liquidationEngine"), liquidationEngine_);
      emit ModifyParameters(bytes32("maxRewardIncreaseDelay"), uint(-1));
      emit ModifyParameters(bytes32("updateDelay"), updateDelay);
      emit ModifyParameters(bytes32("backupUpdateDelay"), backupUpdateDelay);
      emit ModifyParameters(bytes32("baseUpdateCallerReward"), baseUpdateCallerReward);
      emit ModifyParameters(bytes32("maxUpdateCallerReward"), maxUpdateCallerReward);
      emit ModifyParameters(bytes32("perSecondCallerRewardIncrease"), perSecondCallerRewardIncrease);
  }

  // --- Math ---
  uint256 internal constant WAD     = 10 ** 18;
  uint256 internal constant RAY     = 10 ** 27;
  uint256 internal constant ONE     = 1;
  uint256 internal constant HUNDRED = 100;
  function minimum(uint x, uint y) internal pure returns (uint z) {
      z = (x <= y) ? x : y;
  }
  function addition(uint x, uint y) internal pure returns (uint z) {
      require((z = x + y) >= x);
  }
  function subtract(uint x, uint y) internal pure returns (uint z) {
      require((z = x - y) <= x);
  }
  function multiply(uint x, int y) internal pure returns (int z) {
      z = int(x) * y;
      require(int(x) >= 0);
      require(y == 0 || z / y == int(x));
  }
  function multiply(uint x, uint y) internal pure returns (uint z) {
      require(y == 0 || (z = x * y) / y == x);
  }
  function wmultiply(uint x, uint y) internal pure returns (uint z) {
      z = multiply(x, y) / WAD;
  }
  function rmultiply(uint x, uint y) internal pure returns (uint z) {
      z = multiply(x, y) / RAY;
  }
  function rpower(uint x, uint n, uint base) internal pure returns (uint z) {
      assembly {
          switch x case 0 {switch n case 0 {z := base} default {z := 0}}
          default {
              switch mod(n, 2) case 0 { z := base } default { z := x }
              let half := div(base, 2)  // for rounding.
              for { n := div(n, 2) } n { n := div(n,2) } {
                  let xx := mul(x, x)
                  if iszero(eq(div(xx, x), x)) { revert(0,0) }
                  let xxRound := add(xx, half)
                  if lt(xxRound, xx) { revert(0,0) }
                  x := div(xxRound, base)
                  if mod(n,2) {
                      let zx := mul(z, x)
                      if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                      let zxRound := add(zx, half)
                      if lt(zxRound, zx) { revert(0,0) }
                      z := div(zxRound, base)
                  }
              }
          }
      }
  }

  // --- Boolean Logic ---
  function both(bool x, bool y) internal pure returns (bool z) {
      assembly{ z := and(x, y)}
  }
  function either(bool x, bool y) internal pure returns (bool z) {
      assembly{ z := or(x, y)}
  }

  // --- Administration ---
  function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
      if (parameter == "baseUpdateCallerReward") baseUpdateCallerReward = data;
      else if (parameter == "maxUpdateCallerReward") {
        require(data > baseUpdateCallerReward, "CollateralAuctionThrottler/invalid-max-reward");
        maxUpdateCallerReward = data;
      }
      else if (parameter == "perSecondCallerRewardIncrease") {
        require(data >= RAY, "CollateralAuctionThrottler/invalid-reward-increase");
        perSecondCallerRewardIncrease = data;
      }
      else if (parameter == "maxRewardIncreaseDelay") {
        require(data > 0, "CollateralAuctionThrottler/invalid-max-increase-delay");
        maxRewardIncreaseDelay = data;
      }
      else if (parameter == "updateDelay") {
        require(data > 0, "CollateralAuctionThrottler/null-update-delay");
        updateDelay = data;
      }
      else if (parameter == "backupUpdateDelay") {
        require(data > updateDelay, "CollateralAuctionThrottler/invalid-backup-update-delay");
        backupUpdateDelay = data;
      }
      else if (parameter == "globalDebtPercentage") {
        require(both(data > 0, data <= 100), "CollateralAuctionThrottler/invalid-global-debt-percentage");
        globalDebtPercentage = data;
      }
      else revert("CollateralAuctionThrottler/modify-unrecognized-param");
      emit ModifyParameters(parameter, data);
  }
  function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
      require(addr != address(0), "CollateralAuctionThrottler/null-addr");
      if (parameter == "treasury") {
        require(StabilityFeeTreasuryLike(addr).systemCoin() != address(0), "CollateralAuctionThrottler/treasury-coin-not-set");
    	  treasury = StabilityFeeTreasuryLike(addr);
      }
      else if (parameter == "liquidationEngine") {
        liquidationEngine = LiquidationEngineLike(addr);
      }
      else revert("CollateralAuctionThrottler/modify-unrecognized-param");
      emit ModifyParameters(parameter, addr);
  }
  function modifyParameters(uint256 position, address surplusHolder) external isAuthorized {
      (!surplusHolders.isNode(position)) ?
          addSurplusHolder(surplusHolder) :
          modifySurplusHolder(position, surplusHolder);
      emit ModifyParameters(
        position,
        surplusHolder
      );
  }

  // --- Surplus Holder Utils ---
  function addSurplusHolder(address surplusHolder) internal {
      require(surplusHolder != address(0), "CollateralAuctionThrottler/null-account");
      require(usedSurplusHolders[surplusHolder] == 0, "CollateralAuctionThrottler/account-already-used");
      surplusHolderNonce                        = addition(surplusHolderNonce, 1);
      latestSurplusHolder                       = surplusHolderNonce;
      usedSurplusHolders[surplusHolder]         = ONE;
      surplusHolderAccounts[surplusHolderNonce] = surplusHolder;
      surplusHolders.push(latestSurplusHolder, false);
      emit AddSurplusHolder(surplusHolderNonce, latestSurplusHolder, surplusHolder);
  }
  function modifySurplusHolder(uint256 position, address newSurplusHolder) internal {
      if (newSurplusHolder == address(0)) {
        if (position == latestSurplusHolder) {
          (, uint256 prevHolder) = surplusHolders.prev(latestSurplusHolder);
          latestSurplusHolder = prevHolder;
        }
        surplusHolders.del(position);
        delete(usedSurplusHolders[surplusHolderAccounts[position]]);
        delete(surplusHolderAccounts[position]);
      } else {
        surplusHolderAccounts[position] = newSurplusHolder;
      }
      emit ModifySurplusHolder(position, latestSurplusHolder, newSurplusHolder);
  }

  // --- Treasury Utils ---
  function treasuryAllowance() public view returns (uint256) {
      (uint total, uint perBlock) = treasury.getAllowance(address(this));
      return minimum(total, perBlock);
  }
  function getCallerReward() public view returns (uint256) {
      if (lastUpdateTime == 0) return baseUpdateCallerReward;
      uint256 timeElapsed = subtract(now, lastUpdateTime);
      if (timeElapsed < updateDelay) {
          return 0;
      }
      uint256 baseReward   = baseUpdateCallerReward;
      uint256 adjustedTime = subtract(timeElapsed, updateDelay);
      if (adjustedTime > 0) {
          adjustedTime = (adjustedTime > maxRewardIncreaseDelay) ? maxRewardIncreaseDelay : adjustedTime;
          baseReward = rmultiply(rpower(perSecondCallerRewardIncrease, adjustedTime, RAY), baseReward);
      }
      uint256 maxReward = minimum(maxUpdateCallerReward, treasuryAllowance() / RAY);
      if (baseReward > maxReward) {
          baseReward = maxReward;
      }
      return baseReward;
  }
  function rewardCaller(address proposedFeeReceiver, uint256 reward) internal {
      if (address(treasury) == proposedFeeReceiver) return;
      if (either(address(treasury) == address(0), reward == 0)) return;
      address finalFeeReceiver = (proposedFeeReceiver == address(0)) ? msg.sender : proposedFeeReceiver;
      try treasury.pullFunds(finalFeeReceiver, treasury.systemCoin(), reward) {
          emit RewardCaller(finalFeeReceiver, reward);
      }
      catch(bytes memory revertReason) {
          emit FailRewardCaller(revertReason, finalFeeReceiver, reward);
      }
  }

  // --- Recompute Logic ---
  function recomputeOnAuctionSystemCoinLimit(address feeReceiver) public {
      // Check delay between calls
      require(either(subtract(now, lastUpdateTime) >= updateDelay, lastUpdateTime == 0), "CollateralAuctionThrottler/wait-more");
      // Get the caller's reward
      uint256 callerReward = getCallerReward();
      // Store the timestamp of the update
      lastUpdateTime = now;
      // Compute total surplus
      uint256 totalSurplus;
      // Start looping from the latest surplus holder
      uint256 currentSurplusHolder = latestSurplusHolder;
      // While we still haven't gone through the entire list
      while (currentSurplusHolder > 0) {
        totalSurplus = addition(totalSurplus, safeEngine.coinBalance(surplusHolderAccounts[currentSurplusHolder]));
        // Continue looping
        (, currentSurplusHolder) = surplusHolders.prev(currentSurplusHolder);
      }
      // Remove surplus from global debt
      uint256 rawGlobalDebt = subtract(safeEngine.globalDebt(), totalSurplus);
      // Calculate and set the onAuctionSystemCoinLimit
      liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", multiply(rawGlobalDebt / HUNDRED, globalDebtPercentage));
      // Pay the caller for updating the rate
      rewardCaller(feeReceiver, callerReward);
  }
  function backupRecomputeOnAuctionSystemCoinLimit(address feeReceiver) public {
      // Check delay between calls
      require(either(subtract(now, lastUpdateTime) >= backupUpdateDelay, lastUpdateTime > 0), "CollateralAuctionThrottler/wait-more");
      // Get the caller's reward
      uint256 callerReward = getCallerReward();
      // Store the timestamp of the update
      lastUpdateTime = now;
      // Set the onAuctionSystemCoinLimit
      liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", safeEngine.globalDebt());
      // Pay the caller for updating the rate
      rewardCaller(feeReceiver, callerReward);
  }
}
