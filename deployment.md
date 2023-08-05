# VSDB

## Address

1. package address: `0x05335df408c7d3c67b307d44ee85770ff69bd401dad64d2d782ca8552ccaf4e4`
2. VSDBRegistry: `0x5bce44c806d8518009a6fa69c2135827505a50f039928d08515adaf456c524ec`
3. VSDBCap: `0x6150e8d5c894edcdb9f06cb98727afd7b51377abbb20e3fa7473aab6ffdbc1aa`

## entry function commands:

1. lock:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "lock" --args $VSDB_REGISTRY ...
   ```
2. increase_unlock_time:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
   ```
3. increase_unlock_amount:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
   ```
4. merge:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "merge" --args $VSDB_REGISTRY ...
   ```
5. revive:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "revive" --args $VSDB_REGISTRY ...
   ```
6. unlock:
   ```c
   sui client call --gas-budget 10000000 --package $VSDB_PACKAGE --module "vsdb" --function "unlock" --args $VSDB_REGISTRY ...
   ```

# Coin_list

deploy test coins for pool setup (USDC, USDT, ETH, BTC)

## entry function commands:

1. mint_and_transfer:

```c
   sui client call --gas-budget 10000000 --package 0x02 --module coin --function mint_and_transfer --args ... --type-args ...
```

# AMM

## Address

1. package address: `0xdc907ce0ddb0cb429591b8a6d7222dd3f97ce0a42c1770653a3d33623baff199`
2. PoolReg: `0x8d97e259775627888b2c01f991511f3fc8da5c330297e1dad3697313dc2cbfad`
3. PoolCap: `0x75fee1fa3ae722d409a4e60d78d136db3dcb83bccdd325f7b90f3fe57d9dc4cd`

### entry function commands:

1. create_pool:

   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool_reg" --function "create_pool" --args $POOL_REG ..... --type-args ....
   ```

   > Find CoinMetadata Object
   >
   > curl -X POST https://fullnode.mainnet.sui.io:443 -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"suix_getCoinMetadata", "id":"1","params":["coin_type"]}'

1. add_liquidity:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "add_liquidity" --args ... --type-args ...
   ```
1. zap_x:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "zap_x" --args ... --type-args ...
   ```
1. zap_y:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "zap_y" --args ... --type-args ...
   ```
1. remove_liquidity:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "remove_liquidity" --args ... --type-args ...
   ```
1. swap_for_x:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "swap_for_x" --args ... --type-args ...
   ```
1. swap_for_y:
   ```c
   sui client call --gas-budget 10000000 --package $AMM_PACKAGE --module "pool" --function "swap_for_y" --args ... --type-args ...
   ```
