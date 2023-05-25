## deployment flow & process

0. AMM:

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

1. SDB:

   - mint amount of first mint SDB
   - keep the cap
   - airdrop

2. VSDB:

   - mint VSDB for reward from first mint
   - register Voter whitelist module

3. Farm:

   - no SDB pool
   - whitelist some valuable farming pools

4. Minter:

   - start Ve(3,3) model

// curl -X POST https: //fullnode.mainnet.sui.io:443
-H 'Content-Type: application/json'
-d '{
"jsonrpc": "2.0",
"method": "suix_getCoinMetadata",
"id": "1",
"params": [
"0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"
]
}'
