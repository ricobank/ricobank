// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { File } from '../../src/file.sol';
import { Vat }  from '../../src/vat.sol';
import { Vox }  from '../../src/vox.sol';
import { Ball } from '../../src/ball.sol';
import { Handler } from './Handler.sol';
import { RicoSetUp } from "../RicoHelper.sol";

// Uses single WETH ilk and modifies WETH and RICO price during run
contract InvariantFluidPrice is Test, RicoSetUp {
    Handler handler;

    function setUp() external {
        make_bank(false);
        ball.mdn().poke(WETH_REF_TAG);
        handler = new Handler(bank, 2, ball);
        ball.cladapt().ward(address(handler), true);
        handler.init_feeds();
        handler.use_mock_feed();
        File(bank).link('tip', address(handler));

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = Handler.frob.selector;
        selectors[1] = Handler.frob.selector;  // add frob twice to double probability
        selectors[2] = Handler.bail.selector;
        selectors[3] = Handler.keep.selector;
        selectors[4] = Handler.drip.selector;
        selectors[5] = Handler.poke.selector;
        selectors[6] = Handler.mark.selector;
        selectors[7] = Handler.wait.selector;
        selectors[8] = Handler.date.selector;
        selectors[9] = Handler.move.selector;
        targetSelector(FuzzSelector({
            addr:      address(handler),
            selectors: selectors
        }));
    }

    // all invariant tests combined for efficiency
    function invariant_all_fluid() external {
        uint sup  = rico.totalSupply();
        uint joy  = Vat(bank).joy();
        uint debt = Vat(bank).debt();
        uint rest = Vat(bank).rest();
        uint sin  = Vat(bank).sin();
        uint tart = Vat(bank).ilks(WETH_ILK).tart;
        uint rack = Vat(bank).ilks(WETH_ILK).rack;
        uint line = Vat(bank).ilks(WETH_ILK).line;

        // debt invariant
        assertEq(joy + sup, debt);

        // tart invariant. compare as RADs
        assertEq(tart * rack - rest, RAY * (sup + joy) - sin);
        assertLt(tart * RAY, line);
    }
}
