
## ricobank
`ricobank` is an `autobank`.  Rico is an iteration on Rai with some important differences, including but not limited to:
- Tick controller, see `vox`
- Composable price feeds, see `feedbase`
- Endgamed incentive structure, see `feedbase` and `vow`
- Simpler implementation, see everything

## autobank

`autobank` is a generic term for the synthetic asset system used in Dai, Rai, and Rico. The behavior of the synthetic depends on the type of controller used. See [bank.dev/vox](https://bank.dev/vox) for a description of how these controllers can be used to implement synthetics that behave like a variety of instruments, from "wrapped perps" to fiat-like synthetic assets.

### overview

- `ball.sol` -- a single contract that deploys and wires up all contracts in the system
- `vat.sol` -- the core CDP engine
- `vow.sol` -- triggers liquidations and processes debt/surplus auctions
- `vox.sol` -- adjusts `par` and `way`
- `ERC20hook.sol` -- hook `vat` uses to handle ERC20 moves in `vat.frob` and `vat.grab`
- `flow.sol` -- the abstract auction interfaces, and version 1 `flower` which uses UniswapV3 pools for the 'auctions'

### developing

You need `node`/`npm` and `ipfs`.
This repo uses submodules for managing some dependencies.

- `npm run initialize` -- this will perform:
    - `npm install`
    - `npm run download-submodules`
    - `npm run install-submodules`
    - `npm run build:all`
- `npm test -- <your_rpc_url> [forge test options]

Run `npm test` with FOUNDRY_PROFILE=lite to build faster.  Lite mode won't pass gas tests.  Use default for those.

To run js tests, with ipfs daemon running:
- `npm run js-test`


