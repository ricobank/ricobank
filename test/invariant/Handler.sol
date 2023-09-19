// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { BaseHelper} from '../BaseHelper.sol';
import { Gem } from '../../lib/gemfab/src/gem.sol';
import { Vat }  from '../../src/vat.sol';
import { Vow }  from '../../src/vow.sol';
import { Vox }  from '../../src/vox.sol';
import { Hook } from '../../src/hook/hook.sol';
import { File } from '../../src/file.sol';
import { Ball } from '../../src/ball.sol';
import { Bank } from '../../src/bank.sol';
import { MockChainlinkAggregator } from '../../src/test/MockChainlinkAggregator.sol';
import { Feedbase } from '../../lib/feedbase/src/Feedbase.sol';
import { Ploker } from '../../lib/feedbase/src/Ploker.sol';
import { ChainlinkAdapter } from '../../lib/feedbase/src/adapters/ChainlinkAdapter.sol';

contract Handler is Test, BaseHelper {
    uint256   public constant ACTOR_WETH = 1000 * WAD;

    address   public currentActor;
    address   public mock_agg;
    uint256   public mock_mar;
    uint256   public localWeth;  // ghost of total eth given to actors
    uint256   public minPar;     // ghost of lowest value of par
    int256    public artCap;
    address[] public actors;
    bytes32[] public ilks;
    Feedbase  public fb;
    Ploker    public ploker;
    ChainlinkAdapter public cladapt;

    constructor(address payable _bank, uint8 num_actors, Ball ball) {
        bank = _bank;
        ploker = ball.ploker();
        ilks.push(WETH_ILK);
        cladapt = ball.cladapt();
        Gem risk = Vow(bank).RISK();

        for (uint i = 100; i < num_actors + 100; ++i) {
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

        bytes32 _mdn = Vat(bank).geth(WETH_ILK, 'fsrc', empty);
        address mdn  = address(bytes20(_mdn));
        uint par     = Vat(bank).par();
        fb           = File(bank).fb();
        minPar       = par;
        mock_mar     = par;
        (bytes32 val,) = fb.pull(mdn, WETH_REF_TAG);
        artCap       = int(ACTOR_WETH * uint(val) / par);
    }

    function frob(uint256 actorSeed, uint256 urnSeed, int256 ink, int256 art) public _larp_(actorSeed) {
        ink = bound(ink, -int(ACTOR_WETH), int(ACTOR_WETH));
        art = bound(art, -artCap, artCap);
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        Vat(bank).frob(WETH_ILK, urn, abi.encodePacked(ink), art);
    }

    function flash(uint256 actorSeed) public _larp_(actorSeed) {}

    // test must first set handler as tip, then this will push new values for mar
    function mark(bool up) public _self_ {
        mock_mar = up ? mock_mar * 101 / 100 : mock_mar * 100 / 101;
        fb.push(RICO_REF_TAG, bytes32(mock_mar), block.timestamp * 2);
    }

    function bail(uint256 actorSeed, uint256 urnSeed) public _larp_(actorSeed) {
        address urn = actors[bound(urnSeed, 0, actors.length - 1)];
        Vat(bank).bail(WETH_ILK, urn);
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

    function wait(uint8 s) public {
        skip(s);
    }

    // about 1% chance to set a feed stale, otherwise fresh
    function date(uint64 _ent) public _self_ {
        uint high_ttl = block.timestamp;
        uint low_ttl  = 0;
        bytes32[3] memory tags = [XAU_USD_TAG, DAI_USD_TAG, WETH_USD_TAG];
        address agg; uint ttl; uint precision;
        uint ent = uint(_ent);
        uint stale_idx = type(uint).max;
        if (ent * 100 / 99 > type(uint64).max) stale_idx = ent % tags.length;
        for(uint i; i < tags.length; i++) {
            (agg, ttl, precision) = cladapt.configs(tags[i]);
            ttl = i == stale_idx ? low_ttl : high_ttl;
            cladapt.setConfig(tags[i], ChainlinkAdapter.Config(agg, ttl, precision));
        }
        ploker.ploke(WETH_REF_TAG);
        ploker.ploke(RISK_RICO_TAG);
        ploker.ploke(RICO_RISK_TAG);
    }


    // modifies WETH/USD price feed iff use_mock_feed() was called in test setUp()
    // the mock agg reads value set by this in FB, so push to FB a value *= or /= 1.25
    function move(bool up) public _self_ {
        (bytes32 val, uint ttl) = fb.pull(self, WETH_USD_TAG);
        int new_val = int(uint(val));
        new_val = up ? new_val * 5 / 4 : new_val * 4 / 5;
        fb.push(WETH_USD_TAG, bytes32(uint(new_val)), ttl);
    }

    /* --------------------------- non target functions --------------------------- */

    modifier _larp_(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }


    // the prank in _larp_() persists over test runs when they revert, use this to ensure acting as handler
    modifier _self_() {
        vm.startPrank(self);
        vm.stopPrank();
        _;
    }

    // let enough time pass to exceed uni adapter range
    function init_feeds() public _self_ {
        skip(20000);  // current uni adapter range
        ploker.ploke(RISK_RICO_TAG);
        ploker.ploke(RICO_RISK_TAG);
        date(1);
    }

    function use_mock_feed() public _self_ {
        (, uint ttl, uint precision) = cladapt.configs(WETH_USD_TAG);
        (bytes32 orig_val, uint orig_ttl) = cladapt.read(WETH_USD_TAG);

        // create mock chainlink agg, edit price by pushing to feedbase as self
        mock_agg = address(new MockChainlinkAggregator(fb, self, WETH_USD_TAG, 27));
        fb.push(WETH_USD_TAG, orig_val, orig_ttl);

        // set cl adapter to use the mock
        cladapt.setConfig(WETH_USD_TAG, ChainlinkAdapter.Config(mock_agg, ttl, precision));
    }
}
