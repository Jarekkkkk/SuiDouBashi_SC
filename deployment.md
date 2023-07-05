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

5. Voter:

   - voting campaign start

## After deployment

1. SuiDouBashi - update the gauge & distribute fees after every epoch
   - calling `voter::distribute` for every gauge to distribute weekly emissions & fees
   -
