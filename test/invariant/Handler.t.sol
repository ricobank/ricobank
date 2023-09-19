// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Ball } from '../../src/ball.sol';
import { File } from '../../src/file.sol';
import { Vat }  from '../../src/vat.sol';
import { Vox }  from '../../src/vox.sol';
import { Handler } from './Handler.sol';
import { RicoSetUp } from "../RicoHelper.sol";

contract HandlerTest is Test, RicoSetUp {
    Handler handler;

    function setUp() external {
        make_bank(false);
        ball.mdn().poke(WETH_REF_TAG);
        handler = new Handler(bank, 2, ball);
        ball.cladapt().ward(address(handler), true);
        handler.init_feeds();
        handler.use_mock_feed();
        File(bank).link('tip', address(handler));
    }

    function test_handler_frob() public {
        uint ts1 = rico.totalSupply();
        handler.frob(0, 0, int(10 * WAD), int(1 * WAD));
        uint ts2 = rico.totalSupply();

        assertGt(ts2, ts1);
    }

    function test_handler_move() public {
        (bytes32 val1,) = handler.fb().pull(address(ball.mdn()), WETH_REF_TAG);
        handler.move(true);
        ball.mdn().poke(WETH_REF_TAG);
        (bytes32 val2,) = handler.fb().pull(address(ball.mdn()), WETH_REF_TAG);

        assertGt(uint(val2), uint(val1));

        handler.move(false);
        ball.mdn().poke(WETH_REF_TAG);
        (bytes32 val3,) = handler.fb().pull(address(ball.mdn()), WETH_REF_TAG);

        assertLt(uint(val3), uint(val2));
        assertClose(uint(val3), uint(val1), 1_000_000);
    }

    function test_handler_date() public {
        (, uint ttl1) = handler.fb().pull(address(ball.mdn()), WETH_REF_TAG);
        skip(10);
        handler.date(10);
        (, uint ttl2) = handler.fb().pull(address(ball.mdn()), WETH_REF_TAG);

        assertNotEq(ttl1, ttl2);
    }

    function test_handler_bail() public {
        // weth/ref is about 0.8. let actor 1 get unsafe and bail with actor 2.
        // bound() will not change inputs if they're within the range
        handler.frob(0, 0, int(100 * WAD), int(80 * WAD));
        handler.frob(1, 1, int(200 * WAD), int(150 * WAD));

        handler.move(false);
        ball.mdn().poke(WETH_REF_TAG);

        uint ts1 = rico.totalSupply();
        handler.bail(1, 0);
        uint ts2 = rico.totalSupply();

        assertLt(ts2, ts1);
    }

    function test_handler_keep() public {
        handler.frob(0, 0, int(100 * WAD), int(50 * WAD));
        handler.wait(200);

        uint r1 = risk.totalSupply();
        handler.keep(0);
        uint r2 = risk.totalSupply();

        assertLt(r2, r1);
    }

    function test_handler_wait() public {
        uint ts1 = block.timestamp;
        handler.wait(5);
        uint ts2 = block.timestamp;

        assertEq(ts1 + 5, ts2);
    }

    function test_handler_drip() public {
        handler.frob(0, 0, int(100 * WAD), int(50 * WAD));
        handler.wait(200);

        uint j1 = Vat(bank).joy();
        handler.drip();
        uint j2 = Vat(bank).joy();

        assertGt(j2, j1);
    }

    function test_handler_mark_poke() public {
        uint p1 = Vat(bank).par();

        handler.mark(true);
        handler.mark(false);
        handler.wait(10);
        handler.poke();
        handler.wait(10);
        handler.poke();

        uint p2 = Vat(bank).par();
        assertEq(p2, p1);

        handler.mark(true);
        handler.wait(10);
        handler.poke();
        handler.wait(10);
        handler.poke();

        uint p3 = Vat(bank).par();
        assertLt(p3, p2);
    }
}
