## Rico Credit System

RICO is an ERC20 token that's designed to be stable with respect to RISK, an ERC20 token used to purchase accumulated fees from debt positions.

For a brief primer, see the [Litepaper](https://bank.dev/rico1_lite).

### overview

- `bank.sol` -- core RCS functions
- `math.sol` -- internal math funcitons
- `flog.sol` -- external function call events
- `palm.sol` -- storage variable modified events

### developing

You need `node`/`npm`, and you need `ipfs daemon` running.
This repo uses submodules for managing some dependencies.

- `npm run initialize` -- this will perform:
    - `npm install`
    - `npm run download-submodules`
    - `npm run install-submodules`
    - `npm run build:all`
- `FOUNDRY_PROFILE=lite npm test`

To run js tests with `ipfs daemon` running:

- `npm run js-test`

To deploy from hardhat console:

- `pack = await hre.run('deploy-ricobank', { writepack: 'true', netname: <network name from which to load settings>, tokens: './tokens.json', mock: 'true', gasLimit: <gas limit> })`

### dpack

To deploy ricobank and create a new `pack` for it, run the `deploy-ricobank` task.  It will return the pack object and also write it to a json file in ./pack/.  To load the pack,

- `pack = require(path_to_pack_file)` or `pack = hre.run('deploy-ricobank', ...)`
- `dapp = await dpack.load(pack, ethers, signer)`
- `bank = dapp.bank`

`dapp` contains `bank`, the core `ricobank` object and some other contracts, all as ethers.js Contract objects.  

To create a CDP, approve your tokens to `bank`, and run `bank.frob(dink, dart)` using the ethers Solidity ABI.

- `bank.keep()` - balance surplus/deficit and poke the par price
- `bank.bail(usr)` - liquidate a position

