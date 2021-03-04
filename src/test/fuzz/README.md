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

### Contract Fuzz
The contracts main functions, checking desired properties are ```fuzzRecompute``` and ```fuzzBackupRecompute```. They will recompute the threshold and then test ```liquidationEngine.onAuctionSystemCoinLimit()```.

The remaining functions are auxiliary, as follows:

- ```FuzzGlobalDebt()```: Will change the global debt to a random value.
- ```FuzzSurplus()```: Will change the debt surplus to a random value.
- ```fuzzParams()```: Will change throttler parameters to random values.
- ```fuzzRewardParams()```: Will change increasing rewards parameters to random values.

These are optional, if set to public they will shuffle parameters in between calls to the main functions described above. We set bounds for the changes (ensuring a feasible range) and also tested with no bounds at all.

We used a mock version of the contract (in this folder), as well as mock versions of the ```IncreasingTreasuryReimbursement``` and ```GebMath```. Import the GebMath Mock version to force failures on overflows.

#### Results:

Analyzing contract: /Users/fabio/Documents/reflexer/geb-collateral-auction-throttler/src/test/fuzz/CollateralAuctionThrottlerFuzz.sol:Fuzz
assertion in fuzzParams: passed! 🎉
assertion in fuzzGlobalDebt: passed! 🎉
assertion in FuzzSurplus: passed! 🎉
assertion in fuzzRewardParams: passed! 🎉
assertion in fuzzRecompute: passed! 🎉
assertion in fuzzBackupRecompute: passed! 🎉

Seed: -9183176273744272754

Analyzing contract: /Users/fabio/Documents/reflexer/geb-collateral-auction-throttler/src/test/fuzz/CollateralAuctionThrottlerFuzz.sol:Fuzz
assertion in fuzzRewardParams: passed! 🎉
assertion in fuzzParams: passed! 🎉
assertion in fuzzGlobalDebt: passed! 🎉
assertion in FuzzSurplus: passed! 🎉
assertion in fuzzRecompute: passed! 🎉
assertion in fuzzBackupRecompute: passed! 🎉

Seed: -6539240661742412668