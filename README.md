
### developing

You need `node`/`npm` and `ipfs`.
This repo uses submodules for managing some dependencies.

- `npm run download-submodules`
- `npm run install-submodules`
- `npm run build:all`

- `npm run test`

Troubleshooting:

* `npm run download-submodules` -> `fatal: Needed a single revision  \  Unable to find current origin/master revision in submodule path 'lib/balancer-pack'`
    * This is a heisenbug possibly related to github moving default branches from `master` to `main`. In this state, you have all the repos and files,
    but the HEAD is half way through a checkout. Fix each submodule by doing `cd lib/xxx && git restore --staged . && git checkout .` -- from
    here you can proceed to `npm run install-submodules`.
* `npm test` -> `Cannot find module '../lib/gemfab/artifacts/sol/gem.sol/Gem.json'`
    * You need to run `npm run build:all`
* `npm test` -> `FetchError: request to http://127.0.0.1:5001/api/v0/cat?arg=.... failed, reason: connect ECONNREFUSED 127.0.0.1:5001`
    * You need to have `ipfs daemon` running.

