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

contract ERC20Handler is Test, Local, RicoSetUp {
    uint256   public constant ACTOR_WETH = 1000 * WAD;
    uint8     public constant NUM_ACTORS = 2;

    address   public currentActor;
    uint256   public rico_ref_val;
    uint256   public weth_ref_val;
    uint256   public weth_ref_max;
    uint256   public localWeth;  // ghost of total eth given to actors
    uint256   public minPar;     // ghost of lowest value of par
    int256    public artCap;
    address[] public actors;
    bytes32[] public ilks;
    mapping (address actor => int offset) public ink_offset;  // track bailed inter-actor weth

    constructor() {
        deploy_local_deps();
        make_bank();
        File(bank).file('tip.src', bytes32(bytes20(self)));
        ilks.push(WETH_ILK);
        weth_ref_val = WETH_REF_VAL;
        weth_ref_max = weth_ref_val;

        for (uint i = 1; i < NUM_ACTORS + 1; ++i) {
            address actor = vm.addr(i);
            actors.push(actor);
            deal(actor, WAD * 1_000_000);
            deal(WETH, actor, ACTOR_WETH);
            localWeth += ACTOR_WETH;

            vm.prank(actor);
            Gem(WETH).approve(bank, type(uint).max);

            vm.prank(bank);
            risk.mint(actor, WAD * 1_000_000);
        }

        uint par     = Vat(bank).par();
        minPar       = par;
        rico_ref_val = par;
        artCap       = int(ACTOR_WETH * weth_ref_val / par);

        feed.push(RICO_REF_TAG, bytes32(rico_ref_val), block.timestamp * 2);
        feedpush(WETH_REF_TAG, bytes32(weth_ref_val), block.timestamp * 2);
    }

    /* --------------------------- target functions expecting reverts --------------------------- */

    function frob(uint256 actorSeed, uint256 urnSeed, int256 ink, int256 art) public _larp_(actorSeed) {
        ink = bound(ink, -int(ACTOR_WETH), int(ACTOR_WETH));
        art = bound(art, -artCap, artCap);
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        Vat(bank).frob(WETH_ILK, urn, abi.encodePacked(ink), art);

        // ink integrity tracking
        if (urn != currentActor) {
            ink_offset[currentActor] -= ink;
            ink_offset[urn]          += ink;
        }
    }

    function flash(uint256 actorSeed) public _larp_(actorSeed) {}

    // test must first set handler as tip, then this will push new values for mar
    function mark(bool up) public _self_ {
        rico_ref_val = up ? rico_ref_val * 101 / 100 : rico_ref_val * 100 / 101;
        feed.push(RICO_REF_TAG, bytes32(rico_ref_val), block.timestamp * 2);
    }

    function move(bool up) public _self_ {
        weth_ref_val = up ? weth_ref_val * 5 / 4 : weth_ref_val * 4 / 5;
        weth_ref_max = max(weth_ref_max, weth_ref_val);
        feedpush(WETH_REF_TAG, bytes32(weth_ref_val), block.timestamp * 2);
    }

    function bail(uint256 actorSeed, uint256 urnSeed) public _larp_(actorSeed) {
        // track transferred weth for actor weth + ink invariant
        uint pre_weth = Gem(WETH).balanceOf(currentActor);

        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        Vat(bank).bail(WETH_ILK, urn);

        uint aft_weth = Gem(WETH).balanceOf(currentActor);
        int sold = int(aft_weth) - int(pre_weth);
        ink_offset[currentActor] += sold;
        ink_offset[urn]          -= sold;
    }

    function keep(uint256 actorSeed) public _larp_(actorSeed) {
        Vow(bank).keep(ilks);
    }

    function drip() public {
        Vat(bank).drip(WETH_ILK);
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
        bytes32[3] memory tags = [WETH_REF_TAG, RICO_RISK_TAG, RISK_RICO_TAG];
        uint ent = uint(_ent);
        uint stale_idx = type(uint).max;
        if (ent * 100 / 99 > type(uint64).max) stale_idx = ent % tags.length;
        for(uint i; i < tags.length; i++) {
            (bytes32 val,) = feedpull(tags[i]);
            uint ttl = i == stale_idx ? 0 : block.timestamp * 2;
            feedpush(tags[i], val, ttl);
        }
    }

    /* --------------------------- target functions avoiding reverts --------------------------- */

    function norev_frob(uint256 actorSeed, uint256 urnSeed, int256 ink, int256 art) public _larp_(actorSeed) {
        ink = bound(ink, -int(ACTOR_WETH), int(ACTOR_WETH));
        art = bound(art, -artCap, artCap);
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];

        // limit conditions to avoid desired reverts, return before calling frob
        // avoid stealing
        if (currentActor != urn) {
            if (art > 0 || ink < 0) return;
        }
        // avoid ink underflows
        uint pre_ink = abi.decode(Vat(bank).ink(WETH_ILK, urn), (uint));
        uint aft_ink = pre_ink;
        if (ink < 0) {
            if (uint(-ink) > pre_ink) return;
            aft_ink -= uint(-ink);
        } else if (ink > 0) {
            if (uint(ink) > Gem(WETH).balanceOf(currentActor)) return;
            aft_ink += uint(ink);
        }
        // avoid unsafe and dust
        uint256 pre_art = Vat(bank).urns(WETH_ILK, urn);
        uint256 dust = Vat(bank).ilks(WETH_ILK).dust;
        uint256 rack = Vat(bank).ilks(WETH_ILK).rack;
        uint256 price;
        {
            bytes32 val = Vat(bank).geth(WETH_ILK, 'src', empty);
            address src = address(bytes20(val));
            bytes32 tag = Vat(bank).geth(WETH_ILK, 'tag', empty);
            (bytes32 _price,) = feed.pull(src, tag);
            price = uint(_price);
        }
        uint liqr    = uint(Vat(bank).geth(WETH_ILK, 'liqr', empty));

        if (art < 0) {
            // avoid underflow
            if (uint(-art) > pre_art) return;
            // need to own more than amount to burn
            if ((rmul(rack, uint(-art)) + 1) > rico.balanceOf(currentActor)) return;
            // don't leave dust
            uint aft_art = pre_art - uint(-art);
            if (aft_art * rack < dust) return;
            if (ink < 0) {
                // taking away ink so must also be safe
                if ((price * rdiv(aft_ink, liqr)) <= (aft_art * rmul(Vat(bank).par(), rack))) return;
            }
        } else if (art > 0) {
            // avoid dust
            uint aft_art = pre_art + uint(art);
            if (aft_art * rack < dust) return;
            // avoid unsafe
            if ((price * rdiv(aft_ink, liqr)) <= (aft_art * rmul(Vat(bank).par(), rack))) return;
            // avoid going over the line.
            uint pre_tart = Vat(bank).ilks(WETH_ILK).tart;
            if (add(pre_tart, art) * rack > Vat(bank).ilks(WETH_ILK).line) return;
            if ((Vat(bank).debt() + rmul(rack, uint(art)) + Vat(bank).rest() / RAY) > Vat(bank).ceil()) return;
        } else {
            // complete safety check in all cases
            if ((price * rdiv(aft_ink, liqr)) <= (pre_art * rmul(Vat(bank).par(), rack))) return;
        }

        // did not return so not expecting revert, call frob
        Vat(bank).frob(WETH_ILK, urn, abi.encodePacked(ink), art);
        // ink integrity tracking
        if (urn != currentActor) {
            ink_offset[currentActor] -= ink;
            ink_offset[urn]          += ink;
        }
    }

    function norev_flash(uint256 actorSeed) public _larp_(actorSeed) {}

    // test must first set handler as tip, then this will push new values for mar
    function norev_mark(bool up) public _self_ {
        rico_ref_val = up ? rico_ref_val * 101 / 100 : rico_ref_val * 100 / 101;
        feed.push(RICO_REF_TAG, bytes32(rico_ref_val), type(uint).max);
    }

    function norev_move(bool up) public _self_ {
        weth_ref_val = up ? weth_ref_val * 5 / 4 : weth_ref_val * 4 / 5;
        weth_ref_max = max(weth_ref_max, weth_ref_val);
        feedpush(WETH_REF_TAG, bytes32(weth_ref_val), type(uint).max);
    }

    function norev_bail(uint256 actorSeed, uint256 urnSeed) public _larp_(actorSeed) {
        // track transferred weth for actor weth + ink invariant
        uint pre_weth = Gem(WETH).balanceOf(currentActor);

        address urn = actors[bound(urnSeed, 0, actors.length - 1)];

        // return if bail should revert
        uint256 rack = Vat(bank).ilks(WETH_ILK).rack;
        uint256 par  = Vat(bank).par();
        uint price;
        {
            bytes32 val = Vat(bank).geth(WETH_ILK, 'src', empty);
            address src = address(bytes20(val));
            bytes32 tag = Vat(bank).geth(WETH_ILK, 'tag', empty);
            (bytes32 _price,) = feed.pull(src, tag);
            price = uint(_price);
        }
        uint liqr    = uint(Vat(bank).geth(WETH_ILK, 'liqr', empty));
        uint art     = Vat(bank).urns(WETH_ILK, urn);
        uint ink     = abi.decode(Vat(bank).ink(WETH_ILK, urn), (uint));
        // return if the urn is safe
        if ((price * rdiv(ink, liqr)) + 1 >= (art * rmul(par, rack))) return;
        // return if actor has insufficient rico
        if (rmul(price, rdiv(ink, liqr)) > rico.balanceOf(currentActor)) return;

        Vat(bank).bail(WETH_ILK, urn);

        uint aft_weth = Gem(WETH).balanceOf(currentActor);
        int sold = int(aft_weth) - int(pre_weth);
        ink_offset[currentActor] += sold;
        ink_offset[urn]          -= sold;
    }

    function norev_keep(uint256 actorSeed) public _larp_(actorSeed) {
        Bank.Ramp memory ramp = Vow(bank).ramp();
        bool will_flop = (Vat(bank).sin() / RAY) > Vat(bank).joy();

        if (will_flop && block.timestamp == ramp.bel) return;

        Vow(bank).keep(ilks);
    }

    function norev_drip() public {
        Vat(bank).drip(WETH_ILK);
    }

    function norev_poke() public {
        Vox(bank).poke();
        minPar = min(minPar, Vat(bank).par());
    }

    function norev_wait(uint16 s) public {
        skip(s);
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

    function fresh() public _self_ {
        bytes32[2] memory tags = [WETH_REF_TAG, RISK_RICO_TAG];
        for(uint i; i < tags.length; ++i) {
            (bytes32 val,) = feedpull(tags[i]);
            feedpush(tags[i], val, type(uint).max);
        }
    }
}
