# SuiDouBashi

## VSDB

### Address

1. package address: `0x1234`
2. VSDBRegistry: `0x...`

- entry function commands:
  1.  lock:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "lock" --args $VSDB_REGISTRY ...
      ```
  2.  increase_unlock_time:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
      ```
  3.  increase_unlock_amount:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
      ```
  4.  merge:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "merge" --args $VSDB_REGISTRY ...
      ```
  5.  revive:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "revive" --args $VSDB_REGISTRY ...
      ```
  6.  unlock:
      ```c
      sui client call --gas-budget 1000000 --package $VSDB_ADDRESS --module "vsdb" --function "unlock" --args $VSDB_REGISTRY ...
      ```

## AMM

0. VSDB:

   - command:

1. AMM:

   - deploy AMM smart contract
   - create pool_reg
   - create pool

   ### command line

   - sui client call
     --package {pkg_id}
     --module pool_reg
     --function create_pool
     --args
     --type-args
     --gas-budget 10000

2. SDB:

   - mint amount of first mint SDB
   - keep the cap
   - airdrop

3. VSDB:

   - mint VSDB for reward from first mint
   - register Voter whitelist module

4. Farm:

   - no SDB pool
   - whitelist some valuable farming pools

5. Minter:

   - start Ve(3,3) model

6. Voter:

   - voting campaign start

## After deployment

1. SuiDouBashi - update the gauge & distribute fees after every epoch
   - calling `voter::distribute` for every gauge to distribute weekly emissions & fees
   -
