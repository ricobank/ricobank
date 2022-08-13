
## autobank

`autobank` is a generic term for the synthetic asset system used in Dai, Rai, and Rico. The behavior of the synthetic depends on the type of controller used. See [bank.dev/vox](https://bank.dev/vox) for a description of how these controllers can be used to implement synthetics that behave like a variety of instruments, from "wrapped perps" to fiat-like synthetic assets.

### overview

- `abi.sol` -- interfaces used throughout the project
- `ball.sol` -- a single contract that deploys and wires up all contracts in the system
- `flow.sol` -- the abstract auction interfaces, and version 1 `flower` which uses Balancer pools for the 'auctions'
- `plot.sol` -- associates feedbase `src,tag` and variables in `vat`/`vow`, pulls from feedbase / pushes to system
- `plug.sol` -- join/exit/flash for gems
- `port.sol` -- join/exit/flash for rico
- `vat.sol` -- the core CDP engine
- `vow.sol` -- triggers liquidations and processes debt/surplus auctions
- `vox.sol` -- adjusts `par` and `way`


### developing

You need `node`/`npm` and `ipfs`.
This repo uses submodules for managing some dependencies.

- `npm run initialize` -- this will perform:
    - `npm install`
    - `npm run download-submodules`
    - `npm run install-submodules`
    - `npm run build:all`
- `npm run test`


