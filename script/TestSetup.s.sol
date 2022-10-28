// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import { RicoSetUp } from "../test/RicoHelper.sol";
import { WethLike } from "../test/RicoHelper.sol";

contract SetupScript is Script, RicoSetUp {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey  = vm.envAddress("PUBLIC_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);
        make_bank();

        WethLike(WETH).deposit{value: 1000 * WAD}();
        vat.init(wilk, WETH, deployerPublicKey, wtag);
        vat.drip(wilk);
        vat.filk(wilk, 'fee',  1000000001546067052200000000);  // 5%
        vat.list(WETH, true);
        vat.filk(wilk, 'chop', RAD);
        vat.filk(wilk, 'dust', 100 * RAD);
        vat.filk(wilk, 'line', 100000 * RAD);
        feed.push(wtag, bytes32(RAY * 1000), block.timestamp + 1000);
        vow.grant(WETH);

        console.log('vat @ %s, vox at %s, fb @ %s', avat, avox, address(feed));
        vm.stopBroadcast();
    }
}
