// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { RicoSetUp } from "../test/RicoHelper.sol";

contract SetupScript is Script, RicoSetUp {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        make_bank();
        console.log('bank @ %s', address(bank));
        vm.stopBroadcast();
    }
}
