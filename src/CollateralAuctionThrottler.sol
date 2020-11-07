pragma solidity ^0.6.7;

abstract contract LiquidationEngineLike {
  function modifyParameters(bytes32, uint256) virtual external;
}
abstract contract SAFEEngineLike {
  function globalDebt() virtual public view returns (uint256);
  function coinBalance(address) virtual public view returns (uint256);
}

contract CollateralAuctionThrottler {
  LiquidationEngineLike public liquidationEngine;
  SAFEEngineLike        public safeEngine;

  
}
