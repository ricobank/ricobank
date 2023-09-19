// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { RicoSetUp } from "../RicoHelper.sol";
import { Vat }  from '../../src/vat.sol';
import { Ball } from '../../src/ball.sol';
import { Handler } from './Handler.sol';

// Uses single WETH ilk and leaves WETH price fixed
contract InvariantFixedPrice is Test, RicoSetUp {
    Handler handler;

    function setUp() external {
        make_bank(false);
        ball.mdn().poke(WETH_REF_TAG);
        handler = new Handler(bank, 2, ball);
        ball.cladapt().ward(address(handler), true);
        handler.init_feeds();

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = Handler.frob.selector;
        selectors[1] = Handler.frob.selector;  // add frob twice to double probability
        selectors[2] = Handler.bail.selector;
        selectors[3] = Handler.keep.selector;
        selectors[4] = Handler.drip.selector;
        selectors[5] = Handler.poke.selector;
        selectors[6] = Handler.wait.selector;
        selectors[7] = Handler.date.selector;
        targetSelector(FuzzSelector({
            addr:      address(handler),
            selectors: selectors
        }));
    }

    // all invariant tests combined for efficiency
    function invariant_all_fixed() external {
        uint sup  = rico.totalSupply();
        uint joy  = Vat(bank).joy();
        uint debt = Vat(bank).debt();
        uint rest = Vat(bank).rest();
        uint sin  = Vat(bank).sin();
        uint tart = Vat(bank).ilks(WETH_ILK).tart;
        uint rack = Vat(bank).ilks(WETH_ILK).rack;
        uint line = Vat(bank).ilks(WETH_ILK).line;
        uint liqr = Vat(bank).ilks(WETH_ILK).liqr;
        (bytes32 val,) = feed.pull(address(ball.mdn()), WETH_REF_TAG);
        uint weth_val  = handler.localWeth() * uint(val) / handler.minPar();

        // debt invariant
        assertEq(joy + sup, debt);

        // tart invariant. compare as RADs
        assertEq(tart * rack - rest, RAY * (sup + joy) - sin);
        assertLt(tart * RAY, line);

        // assert limit on total possible RICO drawn given fixed WETH price and quantity
        assertLt(sup, rdiv(weth_val, liqr));
    }
}
