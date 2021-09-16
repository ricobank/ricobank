
DSS was developed with the assumption that the solidity compiler could not be trusted to be correct.
In this repo we assume the compiler emits correct output, ie, we tolerate generated
forms that are more complex to formally verify at the EVM level if it simplifies code readability at the solidity level.

Done:

* Use solidity 0.8.6
* * `now` -> `block.timestamp`
* * `uint(-1)` -> `type(uint256).max`
* Use hardhat for build tool

To do:

* `drip` on every touch
* lending rate in vat (jug)
* DSR removed (jar), instead effective via TR (way)
* par/way in vat
* drop `fold`
* move price / liq ratio into vat (division for spot in vat)
* per-ilk accessor addresses. (supports most generic form of auth (all actions by proxy))
* events
* Math mixin
* Ward mixin (auth)
* `vox` TRFM
* join flash loans
* oracle data flow abstracted behind feedbase
* `gemcap` parameter caps gem deposits, is a way to control smart contract risk
* `rate` -> `racc` name
* `duty/rho` in Ilk type instead of outside CDP
* `owed` exposed debt, `feed` on top of `spot`
