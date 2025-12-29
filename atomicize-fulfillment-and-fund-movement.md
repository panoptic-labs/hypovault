## Goal: Make Fulfillment & fund management atomic

#### Smart contract deployment + testing updates

- [ ] Give Manager contract itself a ManageRoot so it can call `fulfillDeposits`
  - [ ] Do it in deploy contracts. Re-run tests and ensure they still work.
  - [ ] In integration test, instead of calling `fulfillDeposits`, then `manageVaultWithMerkleVerification`, add `fulfillDeposits` as the first in the list of calls made via `manageVaultWithMerkleVerification` so that fulfillment and fund approval / movement happens atomically.
    - [ ] Will need to update the MerkleTree helper with a new function, \_addHypoVaultManagerLeafs, that adds fulfillDeposits and fulfillWithdrawals to the merkle tree
    - [ ] Will need to update the CollateralTrackerDecoderAndSanitizer to be named PanopticDecoderAndSanitizer, and add support for `fulfillDeposits` and `fulfillWithdrawals` to the contract

#### Update Managers

- [ ] Change manager code for deposit request handling so that deposit fulfillment and fund movement happen atomically. So, do not call fulfillDeposits on it's own. Instead, when calling `manageVaultWithMerkleVerification`, make the first call in the args `fulfillDeposits`.

- [ ] Re-run tests and ensure they pass

- [ ] Make a similar change for withdrawal request handling. When calling `manageVaultWithMerkleVerification`, make the first call in the args `withdraw` so funds become available for share fullfillment, then make the final call in the args `fulfillWithdrawals`.
