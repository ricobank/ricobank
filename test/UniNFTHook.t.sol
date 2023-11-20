// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Flasher } from "./Flasher.sol";
import {
    RicoSetUp, Guy, WethLike, Ball, Gem, Vat, Vow, File, Bank, Hook
} from "./RicoHelper.sol";
import "./UniHelper.sol";
import '../src/mixin/math.sol';
import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { IERC721, INonfungiblePositionManager } from './Univ3Interface.sol';

contract NFTHookTest is Test, RicoSetUp {
    uint256   init_join = 1000;
    uint      stack     = WAD * 10;
    bytes32[] ilks;
    address[] gems;
    uint256[] wads;
    Flasher   chap;
    address   achap;
    uint      goldwethtokid;
    uint      golddaitokid;

    uint    constant flash_size = 100;
    address constant UNI_NFT_ADDR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function setUp() public {
        make_bank();
        init_gold();
        init_dai();

        // create two tokenIds - one from gold:weth pool and
        // one from gold:dai pool
        uint160 onex96 = 2 ** 96;
        WethLike(WETH).deposit{value: 10000 * WAD}();
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(WETH, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );
        (goldwethtokid,,,) = create_and_join_pool(args);

        args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(DAI, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );
        (golddaitokid,,,) = create_and_join_pool(args);

        IERC721(UNI_NFT_ADDR).approve(bank, goldwethtokid);
        IERC721(UNI_NFT_ADDR).approve(bank, golddaitokid);

        // uni ilk needs feeds and liqrs for all three erc20 tokens - weth dai gold
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(WETH))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(WETH))), wrtag);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))), bytes32(RAY));

        feedpush(wrtag, bytes32(1000 * RAY), type(uint).max);

        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(agold))), grtag);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY));
 
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);

        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(DAI))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(DAI))), drtag);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(DAI))), bytes32(RAY));
        feedpush(drtag, bytes32(RAY), type(uint).max);

        Vat(bank).filk(uilk, 'line', bytes32(100000 * RAD));
        guy = new Guy(bank);
    }

    // basic frob with gold:weth uni nft
    function test_nft_frob() public {
        assertEq(nfpm.ownerOf(goldwethtokid), self);

        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        uint ricobefore = rico.balanceOf(self);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        assertGt(rico.balanceOf(self), ricobefore);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
    }

    function test_id_must_exist() public {
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // should fail to frob if nft doesn't exist
        dink[1] = 2 ** 100;
        vm.expectRevert("ERC721: operator query for nonexistent token");
        Vat(bank).frob(uilk, self, abi.encode(dink), int(0));
    }

    // shouldn't be able to add the same nft twice in same frob
    function test_cant_add_multi_dups() public {
        uint[] memory dink = new uint[](3);
        (dink[0], dink[1], dink[2]) = (1, goldwethtokid, goldwethtokid);
        vm.expectRevert("ERC721: transfer of token that is not own");
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
    }

    // shouldn't be able to add the same nft twice in different frobs
    function test_cant_add_dups() public {
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
        vm.expectRevert("ERC721: transfer of token that is not own");
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
    }

    // number of nfts per urn should be limited
    function test_max_urn_nfts() public {
        uint nft_id;
        uint160 onex96 = 2 ** 96;
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1 * WAD), Asset(WETH, 1 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );

        for(uint i = 0; i < HOOK_ROOM + 1; i++) {
            (nft_id,,,) = join_pool(args);
            IERC721(UNI_NFT_ADDR).approve(bank, nft_id);
            uint[] memory dink = new uint[](2);
            dink[0] = 1; dink[1] = nft_id;
            if(i == HOOK_ROOM) vm.expectRevert(UniNFTHook.ErrFull.selector);
            Vat(bank).frob(uilk, self, abi.encode(dink), int(0));
        }
    }

    function test_nft_bail() public {
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // just gold dip can't make collateral worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);

        // just weth dip can't make collateral worthless
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);

        // both dip, collateral is worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        Vat(bank).bail(uilk, self);
        assertEq(Vat(bank).urns(uilk, self), 0);
        // todo test successful swaps, compare to master
    }

    // flip pricing mechanism
    function test_nft_bail_price() public {
        // the NFT has 1000 each of gold and weth, valued at 1900 and 1000
        // frob to max safe debt with double cratio, 1.45MM rico
        File(bank).file('ceil', bytes32(WAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(gilk, 'line', bytes32(RAD * 1_000_000_000));
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        uint borrow = WAD * uint(2_900_000 - 1);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);

        // set prices to 75%
        feedpush(wrtag, bytes32(750  * RAY), type(uint).max);
        feedpush(grtag, bytes32(1425 * RAY), type(uint).max);

        // price should be 0.75**3, cubed comes from for oracle drop decreasing value, and deal factor ** pep(2)
        uint expected = wmul(borrow, WAD * 75**3 / 100**3);
        // tiny errors from uni pool?
        expected = expected * 10001 / 10000;
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        guy.bail(uilk, self);

        // guy was given about exact amount, check almost all was spent
        assertLt(rico.balanceOf(address(guy)), borrow / 10_000);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
    }

    // excess flip proceeds are sent to user
    function test_nft_bail_refund() public {
        uint pop = RAY * 2;
        Vat(bank).filh(uilk, 'pop', empty, bytes32(pop));

        // the NFT has 1000 each of gold and weth, valued at 1900 and 1000
        // frob to max safe debt with double cratio, 1.45MM rico
        File(bank).file('ceil', bytes32(WAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(gilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(RAY * 2));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY * 2));

        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        uint borrow = WAD * uint(1_450_000 - 1);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        // set prices to 75%
        feedpush(wrtag, bytes32(750 * RAY), type(uint).max);
        feedpush(grtag, bytes32(1425 * RAY), type(uint).max);

        // price should be pop(2) * 0.75**3, as 0.75 for oracle drop and 0.75**2 for deal factor (pep = 2)
        uint expected_cost_for_keeper = rmul(wmul(borrow * 2, WAD * 75**3 / 100**3), pop);

        // tiny errors from uni pool
        expected_cost_for_keeper = expected_cost_for_keeper * 10001 / 10000;

        // mint some rico to fill the bail, then bail
        prepguyrico(expected_cost_for_keeper, false);
        uint self_pre_bail_rico = rico.balanceOf(self);
        guy.bail(uilk, self);

        // although position was overcollateralised full expected amount should be taken
        assertLt(rico.balanceOf(address(guy)), borrow / 1_000);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));

        // refund should be in the form of rico paid to self
        uint refund          = rico.balanceOf(self) - self_pre_bail_rico;
        uint expected_refund = expected_cost_for_keeper - borrow;
        assertClose(refund, expected_refund, 1000);
    }

    // multiple nfts in one urn
    function test_multipos() public {
        // add goldwethtokid and golddaitokid at once
        uint[] memory dink = new uint[](3);
        (dink[0], dink[1], dink[2]) = (1, goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);

        feedpush(drtag, bytes32(RAY / uint(100_000)), type(uint).max);
        (,uint deal,) = Vat(bank).safe(uilk, self);

        // only asset of value is 1000 dai worth 1% -> discount should be 0.01 ^ 2
        uint wad_cost = rmul(WAD, rmul(deal, rmul(deal, deal)));
        rico_mint(WAD, true);
        rico.transfer(address(guy), wad_cost);

        uint guy_rico_before = rico.balanceOf(address(guy));
        guy.bail(uilk, self);
        uint guy_rico_after = rico.balanceOf(address(guy));
        uint bail_price     = guy_rico_before - guy_rico_after;

        assertClose(bail_price, wad_cost, 1_000_000);
        assertLt(rico.balanceOf(address(guy)), guy_rico_before);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
        assertEq(nfpm.ownerOf(golddaitokid), address(guy));
    }

    function test_nft_frob_down() public {
        // add goldwethtokid and golddaitokid at once
        uint[] memory dink = new uint[](3);
        (dink[0], dink[1], dink[2]) = (1, goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        // remove golddaitokid
        dink = new uint[](2);
        (dink[0], dink[1]) = (uint(-int(1)), golddaitokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), self);
        (Vat.Spot spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // put it back
        (dink[0], dink[1]) = (1, golddaitokid);
        nfpm.approve(bank, golddaitokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // remove goldwethtokid
        (dink[0], dink[1]) = (uint(-int(1)), goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), 0);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        assertEq(nfpm.ownerOf(golddaitokid), bank);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // put it back
        (dink[0], dink[1]) = (1, goldwethtokid);
        nfpm.approve(bank, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        // remove both
        dink = new uint[](3);
        (dink[0], dink[1], dink[2]) = (uint(-int(1)), golddaitokid, goldwethtokid);
        rico_mint(100, true); // rounding
        Vat(bank).frob(uilk, self, abi.encode(dink), -int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        assertEq(nfpm.ownerOf(golddaitokid), self);
        assertEq(abi.decode(Vat(bank).ink(uilk, self), (uint[])).length, 0);
    }

    function test_nft_make_unsafe_by_rack() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);

        // add goldwethtokid and golddaitokid at once
        uint[] memory dink = new uint[](3);
        (dink[0], dink[1], dink[2]) = (1, goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(900 * WAD));

        // crash 2/3 tokens...weth keeps it safe
        feedpush(drtag, bytes32(0), type(uint).max);
        (Vat.Spot spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);
        feedpush(grtag, bytes32(0), type(uint).max);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // but now wait a decade...fee accumulator (rack) makes it unsafe
        skip(BANKYEAR * 10);
        Vat(bank).drip(uilk);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        // borrow some rico to fill bail, and bail
        (,uint deal,) = Vat(bank).safe(uilk, self);
        uint wad_cost = rmul(rpow(deal, 2), 1000 * WAD);
        rico_mint(wad_cost, true);
        uint[] memory tok_ids = abi.decode(Vat(bank).bail(uilk, self), (uint[]));

        // assert result returned from bail gives all tokens bought
        assertEq(tok_ids[0], goldwethtokid);
        assertEq(tok_ids[1], golddaitokid);
    }

    function test_dir_zero() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);

        // first word (dir) must be 1 or -1
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (0, goldwethtokid);
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(0));
    }

    // build a urn with a lot of tokenIds, make sure it can be wiped
    function test_frob_down_five() public {
        uint160 onex96 = 2 ** 96;
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(WETH, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );

        // make some extra gold:weth nfts
        uint[4] memory goldwethtokids;
        goldwethtokids[0] = goldwethtokid;
        nfpm.approve(bank, golddaitokid);
        for (uint i = 0; i < 4; i++) {
            (goldwethtokids[i],,,) = join_pool(args);
            nfpm.approve(bank, goldwethtokids[i]);
        }

        // add the gold:dai and gold:weth nfts
        uint[] memory dink = new uint[](6);
        (dink[0], dink[1], dink[2], dink[3], dink[4], dink[5]) = (
            1, golddaitokid, goldwethtokids[0], goldwethtokids[1], goldwethtokids[2],
            goldwethtokids[3]
        );
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // bank owns them all now
        assertEq(nfpm.ownerOf(golddaitokid), bank);
        for (uint i = 0; i < 4; i++) {
            assertEq(nfpm.ownerOf(goldwethtokids[i]), bank);
        }

        // try to remove them all at once
        dink[0] = uint(-int(1));
        rico_mint(100, true); // rounding
        Vat(bank).frob(uilk, self, abi.encode(dink), -int(WAD));

        // self owns them all now
        assertEq(nfpm.ownerOf(golddaitokid), self);
        for (uint i = 0; i < 4; i++) {
            assertEq(nfpm.ownerOf(goldwethtokids[i]), self);
        }

        // add them all back
        nfpm.approve(bank, golddaitokid);
        for (uint i = 0; i < 4; i++) {
            nfpm.approve(bank, goldwethtokids[i]);
        }
        dink[0] = 1;
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // only remove a few
        dink = new uint[](4);
        (dink[0], dink[1], dink[2], dink[3]) = (
            uint(-int(1)), golddaitokid, goldwethtokids[1], goldwethtokids[3]
        );
        Vat(bank).frob(uilk, self, abi.encode(dink), -int(WAD));

        // self owns some, urn owns some
        assertEq(nfpm.ownerOf(golddaitokid), self);
        assertEq(nfpm.ownerOf(goldwethtokids[0]), bank);
        assertEq(nfpm.ownerOf(goldwethtokids[1]), self);
        assertEq(nfpm.ownerOf(goldwethtokids[2]), bank);
        assertEq(nfpm.ownerOf(goldwethtokids[3]), self);
    }

    // test uni hook's getters
    function test_geth() public {
        assertEq(uint(Vat(bank).geth(uilk, 'room', empty)), HOOK_ROOM);
        assertEq(address(bytes20(Vat(bank).geth(uilk, 'wrap', empty))), uniwrapper);
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', empty);

        bytes32 val;
        val = Vat(bank).geth(uilk, 'src', single(bytes32(bytes20(WETH))));
        assertEq(address(bytes20(val)), fsrc);
        val = Vat(bank).geth(uilk, 'tag', single(bytes32(bytes20(WETH))));
        assertEq(val, wrtag);

        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', single(bytes32(bytes20(WETH))));

        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', new bytes32[](2));
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'src', new bytes32[](0));
    }

    function test_filh() public {
        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'blah', empty, bytes32(bytes20(address(nfpm))));
        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'room', new bytes32[](1), bytes32(uint(6)));

        Vat(bank).filh(uilk, 'room', empty, bytes32(uint(5)));
        Vat(bank).filh(uilk, 'wrap', empty, bytes32(bytes20(fsrc)));

        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'blah', single(bytes32(bytes20(fsrc))), bytes32(uint(5)));

        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'src', empty, bytes32(uint(5)));
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'src', new bytes32[](2), bytes32(uint(5)));
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'liqr', empty, bytes32(uint(5)));

        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(fsrc))), bytes32(uint(10)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(fsrc))), bytes32(uint(100)));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(fsrc))), bytes32(uint(100 * RAY)));
    }

    function test_not_found() public {
        // add gold:weth nft but not gold:dai
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // try to remove gold:dai - shouldn't be able to
        (dink[0], dink[1]) = (uint(-int(1)), golddaitokid);
        vm.expectRevert(UniNFTHook.ErrNotFound.selector);
        Vat(bank).frob(uilk, self, abi.encode(dink), -int(WAD/2));

        // should then be able to remove gold:dai after adding it
        dink[0] = 1;
        Vat(bank).frob(uilk, self, abi.encode(dink), 0);
        dink[0] = uint(-int(1));
        Vat(bank).frob(uilk, self, abi.encode(dink), -int(WAD/2));
    }

    // should fail when one of an nft's gems doesn't have a feed
    function test_no_feed() public {
        // weth feed null...frob should fail
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(WETH))), bytes32(uint(0)));
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));

        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        vm.expectRevert();
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // gold feed null...frob should fail
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(WETH))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(uint(0)));
        vm.expectRevert();
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));

        // both feeds non-null...frob should pass
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));
        Vat(bank).frob(uilk, self, abi.encode(dink), int(WAD));
    }

    // make sure pep and pop work in uni hook
    function test_bail_pop_pep_uni() public {
        // set pep and pop to something awk
        uint pep    = 3;
        uint pop    = 5 * RAY;
        uint borrow = 1000 * WAD;
        Vat(bank).filh(uilk, 'pep', empty, bytes32(pep));
        Vat(bank).filh(uilk, 'pop', empty, bytes32(pop));

        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY), UINT256_MAX);
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(WETH))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(WETH))), bytes32(grtag));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(agold))), bytes32(wrtag));

        // urn is overcollateralized 2x
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        // big dip, now unsafe
        feedpush(grtag, bytes32(RAY / 6), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY / 6), UINT256_MAX);

        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(uilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // overcollateralized 2x, price 1/6x -> deal is 1/3
        uint tot  = 2 * borrow / 6;
        uint rush = 3;
        uint est  = rmul(tot, pop) / rush**pep;

        assertClose(paid, est, 1000000000);
    }

    // test_bail_pop_pep_uni, but with liqr > 1
    function test_bail_pop_pep_with_liqr_uni() public {
        // set pep and pop to something awk
        uint pep    = 3;
        uint pop    = 5 * RAY;
        uint borrow = 1000 * WAD;
        uint liqr   = 2 * RAY;
        Vat(bank).filh(uilk, 'pep', empty, bytes32(pep));
        Vat(bank).filh(uilk, 'pop', empty, bytes32(pop));

        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY), UINT256_MAX);
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(WETH))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'src', single(bytes32(bytes20(agold))), bytes32(bytes20(fsrc)));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(WETH))), bytes32(grtag));
        Vat(bank).filh(uilk, 'tag', single(bytes32(bytes20(agold))), bytes32(wrtag));

        // overcollateralized 2x
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        // big dip
        feedpush(grtag, bytes32(RAY / 6), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY / 6), UINT256_MAX);
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(liqr));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(liqr));

        uint pre_rico = rico.balanceOf(self);
        Vat(bank).bail(uilk, self);
        uint aft_rico = rico.balanceOf(self);
        uint paid     = pre_rico - aft_rico;

        // overcollateralized 2x, price 1/6x , and liqr 2 -> deal = 1 / 6
        uint tot  = 2 * borrow / 6;
        uint rush = 6;
        uint est  = rmul(tot, pop) / rush**pep;

        assertClose(paid, est, 1000000000);
    }

    // test defensive line
    function test_bail_uni_moves_line() public {
        uint borrow = WAD * 2000 - 10;
        uint line0  = RAD * 2000;
        uint liqr   = RAY * 1;

        Vat(bank).filk(uilk, 'line', bytes32(line0));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(liqr));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(liqr));
        Vat(bank).filh(uilk, "pep",  empty, bytes32(uint(1)));
        Vat(bank).filh(uilk, "pop",  empty, bytes32(RAY));
        feedpush(grtag, bytes32(RAY), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY), UINT256_MAX);

        // frob to edge of safety and line
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        feedpush(grtag, bytes32(RAY / 2), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY / 2), UINT256_MAX);

        Vat(bank).bail(uilk, self);
        uint line1 = Vat(bank).ilks(uilk).line;

        // was initially at limits of line and art, and price dropped to half
        // rico recovery will be borrowed amount * 0.5 for price, * 0.5 for deal
        // line should have decreased to 25% capacity
        assertClose(line0 / 4, line1, 1_000_000_000);

        IERC721(UNI_NFT_ADDR).approve(bank, goldwethtokid);
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow) / 3);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow) / 4);

        // fees or line modifications can lead to loss > capacity, check no underflow
        Vat(bank).filk(uilk, 'line', bytes32(line0 / 10));
        feedpush(grtag, bytes32(RAY / 10), UINT256_MAX);
        feedpush(wrtag, bytes32(RAY / 10), UINT256_MAX);
        Vat(bank).bail(uilk, self);

        uint line2 = Vat(bank).ilks(uilk).line;
        assertEq(line2, 0);
    }

    // different gems have different liqrs
    // any given nft should have effective liqr = max(liqr_tok0, liqr_tok1)
    function test_combined_liqr() public {
        File(bank).file('ceil', bytes32(WAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(gilk, 'line', bytes32(RAD * 1_000_000_000));

        // the NFT has 1000 each of gold and weth, valued at 1900 and 1000
        uint[] memory dink = new uint[](2);
        (dink[0], dink[1]) = (1, goldwethtokid);
        uint borrow = WAD * uint(2_900_000 - 1);

        // safe debt level should come from the safest liqr of either token
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(RAY * 1));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY * 100 / 99));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(RAY * 100 / 99));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY * 1));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));

        // with both liqr at 1.0 same frob should pass
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(WETH))),  bytes32(RAY * 1));
        Vat(bank).filh(uilk, 'liqr', single(bytes32(bytes20(agold))), bytes32(RAY * 1));
        Vat(bank).frob(uilk, self, abi.encode(dink), int(borrow));
    }

    function test_uni_errors_1() public {
        // can do this one just from the hook
        assertFalse(nfthook.frobhook(Hook.FHParams(self, uilk, self, '', 1)));

        // frob up for someone else
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, '', 1));

        // frob down for someone else
        assertTrue(nfthook.frobhook(Hook.FHParams(self, uilk, agold, '', -int(1))));

        // lock ink for someone else
        uint[] memory dink = new uint[](1); dink[0] = 1;
        assertTrue(nfthook.frobhook(Hook.FHParams(
            self, uilk, agold, abi.encode(dink), 0)
        ));

        // unlock ink for someone else
        dink[0] = uint(-int(1));
        vm.expectRevert(Bank.ErrWrongUrn.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, abi.encode(dink), 0));

        // dink not (int,uint,uint...)
        // single uint8 - should be read as an 8-bit direction, so <= 255
        uint8[] memory dink8 = new uint8[](1); dink8[0] = uint8(-int8(1));
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, abi.encode(dink8), 0));

        // single uint40, similar to previous
        uint40[] memory dink40 = new uint40[](1); dink40[0] = uint40(-int40(1));
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, abi.encode(dink40), 0));

        // (uint256, uint8), but tokenId 4 doesn't exist
        //vm.expectRevert(UniNFTHook.ErrNotFound.selector);
        dink8 = new uint8[](2);
        (dink8[0], dink8[1]) = (uint8(-int8(1)), 4);
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, abi.encode(dink8), 0));

        // set dir to something that won't be truncated
        // should fail because self doesn't own tokenId 4
        dink8[0] = 1;
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        nfthook.frobhook(Hook.FHParams(self, uilk, agold, abi.encode(dink8), 0));

        nfthook.file('room', uilk, empty, bytes32(uint(1)));
        IERC721(UNI_NFT_ADDR).approve(address(nfthook), goldwethtokid);
        IERC721(UNI_NFT_ADDR).approve(address(nfthook), golddaitokid);

        // not enough room
        dink = new uint[](3);
        dink[0] = 1; dink[1] = golddaitokid; dink[2] = goldwethtokid;
        vm.expectRevert(UniNFTHook.ErrFull.selector);
        nfthook.frobhook(Hook.FHParams(self, uilk, self, abi.encode(dink), 0));

        // fix room
        nfthook.file('room', uilk, empty, bytes32(uint(10)));
        assertTrue(nfthook.frobhook(Hook.FHParams(self, uilk, self, abi.encode(dink), 0)));

        // more |dink| than ink
        dink = new uint[](4);
        (dink[0], dink[1], dink[2], dink[3]) = (
            uint(-int(1)), golddaitokid, goldwethtokid, golddaitokid
        );
        vm.expectRevert(UniNFTHook.ErrNotFound.selector);
        assertFalse(nfthook.frobhook(Hook.FHParams(self, uilk, self, abi.encode(dink), 0)));

        // not found
        dink = new uint[](2);
        (dink[0], dink[1]) = (uint(-int(1)), 100);
        vm.expectRevert(UniNFTHook.ErrNotFound.selector);
        assertFalse(nfthook.frobhook(Hook.FHParams(self, uilk, self, abi.encode(dink), 0)));
    }

    // null frobs shouldn't revert, but shouldn't add anything
    function test_uni_zero_frobhook() public {
        // including ''
        assertTrue(nfthook.frobhook(Hook.FHParams(self, uilk, self, '', 0)));

        uint[] memory dink = new uint[](1);
        dink[0] = 1;
        assertTrue(nfthook.frobhook(Hook.FHParams(
            self, uilk, self, abi.encode(dink), 0)
        ));

        dink[0] = uint(-int(1));
        assertFalse(nfthook.frobhook(Hook.FHParams(
            self, uilk, self, abi.encode(dink), 0)
        ));

        dink[0] = 0;
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        assertFalse(nfthook.frobhook(Hook.FHParams(
            self, uilk, self, abi.encode(dink), 0)
        ));
    }

    function setrico(address hook, address _rico) internal {
        bytes32 bank_info = 'ricobank.0';
        bytes32 bank_pos = keccak256(abi.encodePacked(bank_info));
        // rico @idx 0
        vm.store(hook, bank_pos,  bytes32(uint(bytes32(bytes20(_rico))) >> (12 * 8)));
    }

    function test_empty_ink_bailhook() public {
        setrico(address(nfthook), address(rico));
        rico.ward(address(nfthook), true);
        Hook.BHParams memory p = Hook.BHParams(uilk, self, WAD, WAD, self, 0, WAD);
        uint[] memory ids = abi.decode(nfthook.bailhook(p), (uint[]));
        assertEq(ids.length, 0);
    }

    function test_dink_has_no_dir() public {
        uint[] memory dink;
        vm.expectRevert(); // index out of bounds
        nfthook.frobhook(Hook.FHParams(self, uilk, self, abi.encode(dink), 0));
    }
}
