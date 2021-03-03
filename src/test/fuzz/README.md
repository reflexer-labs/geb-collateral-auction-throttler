# Security Tests

The contracts in this folder are the fuzz and symbolic execution scripts for the collateral auction throttling contract.

## Fuzz

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/CollateralAuctionThrottlerFuzz.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in the root of this repo (echidna.yaml). You can set the number of and depth of runs,

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should only run one at a time because they interfere with each other.

