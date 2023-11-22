// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Gem } from "../../lib/gemfab/src/gem.sol";
import { Vat }  from "../../src/vat.sol";
import { Vox }  from "../../src/vox.sol";
import { BaseHelper } from "../BaseHelper.sol";
import { UniV3Handler } from "./handlers/UniV3Handler.sol";

// Uses single WETH ilk and modifies WETH and RICO price during run
contract InvariantUniHook is Test, BaseHelper {
    UniV3Handler handler;
    uint256 cap;
    uint256 icap;
    Vat vat;
    Vox vox;
    Gem rico;

    function setUp() external {
        handler = new UniV3Handler();
        bank    = handler.bank();
        rico    = handler.rico();
        vat     = Vat(bank);
        vox     = Vox(bank);
        cap     = vox.cap();
        icap    = rinv(cap);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = UniV3Handler.frob.selector;
        selectors[1] = UniV3Handler.frob.selector;  // add frob twice to double probability
        selectors[2] = UniV3Handler.bail.selector;
        selectors[3] = UniV3Handler.keep.selector;
        selectors[4] = UniV3Handler.drip.selector;
        selectors[5] = UniV3Handler.poke.selector;
        selectors[6] = UniV3Handler.mark.selector;
        selectors[7] = UniV3Handler.wait.selector;
        selectors[8] = UniV3Handler.date.selector;
        selectors[9] = UniV3Handler.move.selector;
        targetSelector(FuzzSelector({
            addr:      address(handler),
            selectors: selectors
        }));
    }

    // all invariant tests combined for efficiency
    function invariant_uni_core() external {
        uint sup  = rico.totalSupply();
        uint joy  = vat.joy();
        uint debt = vat.debt();
        uint rest = vat.rest();
        uint sin  = vat.sin();
        uint tart = vat.ilks(uilk).tart;
        uint rack = vat.ilks(uilk).rack;
        uint line = vat.ilks(uilk).line;
        uint way  = vox.way();

        // debt invariant
        assertEq(joy + sup, debt);
        // tart invariant. compare as RADs. unchecked - ok if both are equally negative
        unchecked {
            assertEq(tart * rack - rest, RAY * (sup + joy) - sin);
        }
        assertLt(tart * RAY, line);

        // way stays within bounds given owner does not file("cap")
        assertLe(way, cap);
        assertGe(way, icap);
    }
}
