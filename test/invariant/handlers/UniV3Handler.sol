// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { VmSafe } from "lib/forge-std/src/Vm.sol";

import { RicoSetUp } from "../../RicoHelper.sol";
import { Gem } from "../../../lib/gemfab/src/gem.sol";
import { Vat }  from "../../../src/vat.sol";
import { Vow }  from "../../../src/vow.sol";
import { Vox }  from "../../../src/vox.sol";
import { Bank } from "../../../src/bank.sol";
import { File } from "../../../src/file.sol";
import { Local } from "../Local.sol";
import { IERC721, INonfungiblePositionManager } from "../../Univ3Interface.sol";
import "../../UniHelper.sol";

contract UniV3Handler is Test, Local, RicoSetUp {
    uint256   public constant LP_AMOUNT = 100 * WAD;
    uint8     public constant NUM_ACTORS = 2;
    uint256   public constant SELF_MINT = LP_AMOUNT * NUM_ACTORS * 100;

    address   public currentActor;
    uint256   public rico_ref_val;
    uint256   public weth_ref_val;
    uint256   public gold_ref_val;
    uint256   public minPar;     // ghost of lowest value of par
    int256    public artCap;
    address[] public actors;
    bytes32[] public ilks;
    uint256[] public positions;  // all positions shared by actors

    constructor() {
        // Shouldn't be run as fork test as very slow, but allow it to construct rather than overwrite code
        bool fork_test = block.number > 1000;
        if (!fork_test)
            deploy_local_deps();

        make_bank();
        File(bank).file('tip.src', bytes32(bytes20(self)));
        ilks.push(uilk);
        init_gold();
        Gem weth = Gem(WETH);
        create_pool(agold, WETH, 500, X96);

        // uni ilk needs feeds and liqrs for both erc20 tokens - weth and gold
        Vat(bank).filh(uilk, 'src',  single(bytes32(bytes20(WETH))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag',  single(bytes32(bytes20(WETH))), wrtag);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))), bytes32(RAY * 11 / 10));
        feedpush(wrtag, bytes32(WETH_REF_VAL), type(uint).max);

        Vat(bank).filh(uilk, 'src',  single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag',  single(bytes32(bytes20(agold))), grtag);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY));
        feedpush(grtag, bytes32(GOLD_REF_VAL), type(uint).max);

        weth_ref_val = WETH_REF_VAL;
        gold_ref_val = GOLD_REF_VAL;

        deal(WETH,  self, SELF_MINT);
        deal(agold, self, SELF_MINT);
        uint gold0 = gold.balanceOf(self);
        uint weth0 = weth.balanceOf(self);

        Vat(bank).filk(uilk, 'line', bytes32(100000 * RAD));

        weth.approve(address(nfpm), type(uint).max);
        gold.approve(address(nfpm), type(uint).max);

        for (uint i = 1; i < NUM_ACTORS + 1; ++i) {
            address actor = vm.addr(i);
            actors.push(actor);
            deal(actor, WAD * 1_000_000);

            vm.prank(bank);
            risk.mint(actor, WAD * 1_000_000);

            // initial version - each actor gets room + 1 liquidity positions of equal size and range
            PoolArgs memory args = PoolArgs(
                Asset(agold, LP_AMOUNT),
                Asset(WETH,  LP_AMOUNT),
                500, X96, X96 * 3 / 4, X96 * 4 / 3, 10, actor
            );
            uint nft_id;
            for (uint j = 0; j < HOOK_ROOM + 1; ++j) {
                (nft_id,,,) = join_pool(args);
                positions.push(nft_id);
            }
        }

        uint par     = Vat(bank).par();
        minPar       = par;
        rico_ref_val = par;
        artCap       = int(LP_AMOUNT * (weth_ref_val + gold_ref_val) / par);
        artCap       = artCap * 4 / 3;

        uint dist_gold = gold0 - gold.balanceOf(self);
        uint dist_weth = weth0 - weth.balanceOf(self);
        uint line = dist_gold * gold_ref_val + dist_weth * weth_ref_val;
        line = line * 4 / 3;
        Vat(bank).filk(uilk, 'line', bytes32(line));

        feed.push(RICO_REF_TAG, bytes32(rico_ref_val), block.timestamp * 2);
        feedpush(WETH_REF_TAG, bytes32(weth_ref_val), block.timestamp * 2);
        feedpush(grtag,        bytes32(gold_ref_val), block.timestamp * 2);
    }

    /* --------------------------- target functions expecting reverts --------------------------- */

    function frob(uint256 actorSeed, uint256 urnSeed, uint256 tok, bool dir, int256 art) public _larp_(actorSeed) {
        // positions created at init, attempt frob any in or out 1 at a time
        uint[] memory dink = new uint[](2);
        uint _dir = dir ? LOCK : FREE;
        uint idx  = bound(tok, 0, positions.length - 1);
        uint tokid = positions[idx];
        (dink[0], dink[1]) = (_dir, tokid);
        art = bound(art, -artCap, artCap);
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        if (_dir == LOCK) IERC721(address(nfpm)).approve(bank, tokid);
        Vat(bank).frob(uilk, urn, abi.encode(dink), art);
    }

    // test must first set handler as tip, then this will push new values for mar
    function mark(bool up) public _self_ {
        rico_ref_val = up ? rico_ref_val * 101 / 100 : rico_ref_val * 100 / 101;
        feed.push(RICO_REF_TAG, bytes32(rico_ref_val), block.timestamp * 2);
    }

    function move(bool weth_up, bool gold_up) public _self_ {
        weth_ref_val = weth_up ? weth_ref_val * 5 / 4 : weth_ref_val * 4 / 5;
        feedpush(WETH_REF_TAG, bytes32(weth_ref_val), block.timestamp * 2);

        gold_ref_val = gold_up ? gold_ref_val * 5 / 4 : gold_ref_val * 4 / 5;
        feedpush(grtag, bytes32(gold_ref_val), block.timestamp * 2);
    }

    function bail(uint256 actorSeed, uint256 urnSeed) public _larp_(actorSeed) {
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        Vat(bank).bail(WETH_ILK, urn);
    }

    function keep(uint256 actorSeed) public _larp_(actorSeed) {
        Vow(bank).keep(ilks);
    }

    function drip() public {
        Vat(bank).drip(uilk);
    }

    function poke() public {
        Vox(bank).poke();
        minPar = min(minPar, Vat(bank).par());
    }

    function wait(uint16 s) public {
        skip(s);
    }

    // about 1% chance to set a feed stale, otherwise fresh
    function date(uint64 _ent) public _self_ {
        bytes32[4] memory tags = [WETH_REF_TAG, grtag, RICO_RISK_TAG, RISK_RICO_TAG];
        uint ent = uint(_ent);
        uint stale_idx = type(uint).max;
        if (ent * 100 / 99 > type(uint64).max) stale_idx = ent % tags.length;
        for(uint i; i < tags.length; i++) {
            (bytes32 val,) = feedpull(tags[i]);
            uint ttl = i == stale_idx ? 0 : block.timestamp * 2;
            feedpush(tags[i], val, ttl);
        }
    }

    /* --------------------------- non target functions --------------------------- */

    modifier _larp_(uint256 actorSeed) {
        clear_prank();
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    // the prank in _larp_() persists over test runs when they revert, use this to ensure acting as handler
    modifier _self_() {
        clear_prank();
        _;
    }

    function clear_prank() internal {
        (VmSafe.CallerMode caller_mode,,) = vm.readCallers();
        if (caller_mode != VmSafe.CallerMode.None) vm.stopPrank();
    }
}
