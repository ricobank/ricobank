// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp, Guy, WethLike } from "./RicoHelper.sol";
import "./UniHelper.sol";
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import '../src/mixin/lock.sol';
import '../src/mixin/math.sol';
import { OverrideableGem } from './mixin/OverrideableGem.sol';
import { UniNFTHook, DutchNFTFlower } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { IERC721, INonfungiblePositionManager } from './Univ3Interface.sol';

contract NFTHookTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address[] gems;
    uint256[] wads;
    Flasher public chap;
    address public achap;
    uint public constant flash_size = 100;
    uint goldwethtokid;
    uint golddaitokid;
    address constant public UNI_NFT_ADDR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function setUp() public {
        make_bank();
        init_gold();
        init_dai();
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
        IERC721(UNI_NFT_ADDR).approve(address(nfthook), goldwethtokid);
        IERC721(UNI_NFT_ADDR).approve(address(nfthook), golddaitokid);

        nfthook.wire(uilk, WETH, address(mdn), wrtag);
        feedpush(wrtag, bytes32(1000 * RAY), type(uint).max);
        nfthook.wire(uilk, agold, address(mdn), grtag);
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);
        nfthook.wire(uilk, DAI, address(mdn), drtag);
        feedpush(drtag, bytes32(RAY), type(uint).max);

        vat.filk(uilk, 'line', 100000 * RAD);
        guy = new Guy(avat, address(nftflow));
    }

    function test_nft_frob() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        uint ricobefore = rico.balanceOf(self);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        vat.frob(':uninft', self, addgwpos, int(WAD));
        assertGt(rico.balanceOf(self), ricobefore);
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
    }

    function test_id_must_exist() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        vat.frob(':uninft', self, addgwpos, int(WAD));
        uint fake_id = 2 ** 100;
        bytes memory add_fake_pos = abi.encodePacked(int(1), fake_id);
        vm.expectRevert("ERC721: operator query for nonexistent token");
        vat.frob(':uninft', self, add_fake_pos, int(0));
    }

    function test_cant_add_multi_dups() public {
        bytes memory add_dup_pos = abi.encodePacked(int(1), goldwethtokid, goldwethtokid);
        vm.expectRevert("ERC721: transfer of token that is not own");
        vat.frob(':uninft', self, add_dup_pos, int(WAD));
    }

    function test_cant_add_dups() public {
        bytes memory add_gw_pos = abi.encodePacked(int(1), goldwethtokid);
        vat.frob(':uninft', self, add_gw_pos, int(WAD));
        vm.expectRevert("ERC721: transfer of token that is not own");
        vat.frob(':uninft', self, add_gw_pos, int(WAD));
    }

    function test_max_urn_nfts() public {
        uint nft_id;
        uint160 onex96 = 2 ** 96;
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1 * WAD), Asset(WETH, 1 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );

        for(uint i = 0; i < HOOK_ROOM + 1; i++) {
            (nft_id,,,) = join_pool(args);
            IERC721(UNI_NFT_ADDR).approve(address(nfthook), nft_id);
            bytes memory add_pos = abi.encodePacked(int(1), nft_id);
            if(i == HOOK_ROOM) vm.expectRevert(UniNFTHook.ErrFull.selector);
            vat.frob(':uninft', self, add_pos, int(0));
        }
    }

    function test_nft_bail() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        vat.frob(':uninft', self, addgwpos, int(WAD));

        // just gold dip can't make collateral worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(':uninft', self);
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);

        // just weth dip can't make collateral worthless
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(':uninft', self);


        // both dip, collateral is worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        uint aid = vow.bail(':uninft', self);
        assertEq(vat.urns(':uninft', self), 0);
        assertGt(aid, 0);
    }

    function test_nft_glug() public {
        nfthook.pair('fade', RAY * 99 / 100);
        nfthook.pair('fuel', 1000 * RAY);
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        vat.frob(':uninft', self, addgwpos, int(WAD));
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        uint aid = vow.bail(':uninft', self);

        rico.approve(address(nftflow), type(uint).max);

        // can't glug at same time as bail
        vm.expectRevert(stdError.arithmeticError);
        nftflow.glug{value: rmul(block.basefee, FUEL)}(aid);

        // not enough rico
        vm.expectRevert(Gem.ErrUnderflow.selector);
        skip(glug_delay);
        nftflow.glug{value: rmul(block.basefee, FUEL)}(aid);
        rico_mint(1000 * WAD, true);

        // a little lower, but still lots to flowback
        skip(30);
        uint price = nftflow.deal(aid, block.timestamp);
        rico.transfer(address(guy), price);
        guy.approve(arico, address(nftflow), type(uint).max);

        uint gim = rmul(block.basefee, FUEL);
        uint ricobefore = rico.balanceOf(self);
        guy.glug{value: gim}(aid);
        assertGt(rico.balanceOf(self), ricobefore);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
    }

    function test_multipos() public {
        nfthook.pair('fade', RAY * 99 / 100);
        nfthook.pair('fuel', 1000 * RAY);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        vat.frob(':uninft', self, data, int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
        assertEq(nfpm.ownerOf(golddaitokid), address(nfthook));

        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(':uninft', self);

        feedpush(drtag, bytes32(0 * RAY), type(uint).max);
        uint gas = gasleft();
        uint aid = vow.bail(':uninft', self);
        check_gas(gas, 432101);

        skip(30);
        uint price = nftflow.deal(aid, block.timestamp);
        rico_mint(1000 * WAD, true);
        rico.transfer(address(guy), price);
        guy.approve(arico, address(nftflow), type(uint).max);

        uint gim = rmul(block.basefee, FUEL);
        uint ricobefore = rico.balanceOf(self);
        gas = gasleft();
        guy.glug{value: gim}(aid);
        check_gas(gas, 265434);
        assertGt(rico.balanceOf(self), ricobefore);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
        assertEq(nfpm.ownerOf(golddaitokid), address(guy));
    }

    function test_nft_frob_down() public {
        nfthook.pair('fade', RAY * 99 / 100);
        nfthook.pair('fuel', 1000 * RAY);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        vat.frob(':uninft', self, data, int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
        assertEq(nfpm.ownerOf(golddaitokid), address(nfthook));

        // remove golddaitokid
        data = abi.encodePacked(-int(1), uint(1));
        vat.frob(':uninft', self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
        assertEq(nfpm.ownerOf(golddaitokid), self);
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));


        // put it back
        data = abi.encodePacked(int(1), golddaitokid);
        nfpm.approve(address(nfthook), golddaitokid);
        vat.frob(':uninft', self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
        assertEq(nfpm.ownerOf(golddaitokid), address(nfthook));
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));

        // remove goldwethtokid
        data = abi.encodePacked(-int(1), uint(0));
        vat.frob(':uninft', self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        assertEq(nfpm.ownerOf(golddaitokid), address(nfthook));
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));

        // put it back
        data = abi.encodePacked(int(1), goldwethtokid);
        nfpm.approve(address(nfthook), goldwethtokid);
        vat.frob(':uninft', self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), address(nfthook));
        assertEq(nfpm.ownerOf(golddaitokid), address(nfthook));
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));
    }

    function test_nft_make_unsafe_by_rack() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);
        nfthook.pair('fade', RAY * 99 / 100);
        nfthook.pair('fuel', 1000 * RAY);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        vat.frob(':uninft', self, data, int(900 * WAD));

        feedpush(drtag, bytes32(0), type(uint).max);
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));
        feedpush(grtag, bytes32(0), type(uint).max);
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Safe));

        skip(BANKYEAR * 10);
        vow.drip(':uninft');
        assertEq(uint(vat.safe(':uninft', self)), uint(Vat.Spot.Sunk));

        vow.bail(':uninft', self);
    }

    function test_dir_zero() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);
        nfthook.pair('fade', RAY * 99 / 100);
        nfthook.pair('fuel', 1000 * RAY);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(0));
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        vat.frob(':uninft', self, data, int(0));
    }

}
