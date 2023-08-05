# VSDB

## Address

1. package address: `0x1234`
2. VSDBRegistry: `0x...`

## entry function commands:

1. lock:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "lock" --args $VSDB_REGISTRY ...
   ```
2. increase_unlock_time:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
   ```
3. increase_unlock_amount:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "increase_unlock_time" --args $VSDB_REGISTRY ...
   ```
4. merge:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "merge" --args $VSDB_REGISTRY ...
   ```
5. revive:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "revive" --args $VSDB_REGISTRY ...
   ```
6. unlock:
   ```c
   sui client call --gas-budget 1000000 --package $VSDB_PACKAGE --module "vsdb" --function "unlock" --args $VSDB_REGISTRY ...
   ```

# Coin_list

deploy test coins for pool setup (USDC, USDT, ETH, BTC)

# AMM

## Address

1. package address: `0x1234`
2. PoolReg: `0x...`

### entry function commands:

1. create_pool:

   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool_reg" --function "create_pool" --args $POOL_REG ..... --type-args ....
   ```

   > Find CoinMetadata Object
   >
   > curl -X POST https://fullnode.mainnet.sui.io:443 -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"suix_getCoinMetadata", "id":"1","params":["coin_type"]}'

1. add_liquidity:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "add_liquidity" --args ... --type-args ...
   ```
1. zap_x:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "zap_x" --args ... --type-args ...
   ```
1. zap_y:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "zap_y" --args ... --type-args ...
   ```
1. remove_liquidity:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "remove_liquidity" --args ... --type-args ...
   ```
1. swap_for_x:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "swap_for_x" --args ... --type-args ...
   ```
1. swap_for_y:
   ```c
   sui client call --gas-budget 1000000 --package $AMM_PACKAGE --module "pool" --function "swap_for_y" --args ... --type-args ...
   ```
