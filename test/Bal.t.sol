// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { RicoSetUp, WethLike } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./BalHelper.sol";
import { BalancerV2Types, BalancerV2VaultLike, IAsset } from '../src/swap.sol';
import { Gem } from "../lib/gemfab/src/gem.sol";

contract BalTest is Test, RicoSetUp {

    WethLike weth = WethLike(WETH);
    address me;
    BalancerV2VaultLike bvault;

    function setUp() public {
        me = address(this);
        make_bank(me);
        rico.mint(me, 10000 * WAD);
        weth.deposit{value: 10000 * WAD}();
        bvault = BalancerV2VaultLike(BAL_VAULT);
        rico.approve(BAL_VAULT, type(uint).max);
        weth.approve(BAL_VAULT, type(uint).max);
    }

    function test_bal_pool_setup() public {
        Asset memory weth_asset = Asset(WETH, 5 * WAD / 10, 1000 * WAD);
        Asset memory rico_asset = Asset(arico, 5 * WAD / 10, 1000 * WAD);

        PoolArgs memory weth_rico_args = PoolArgs(weth_asset, rico_asset, "mock", "MOCK", WAD / 100);

        bytes32 pool_id_weth_rico = create_and_join_pool(weth_rico_args);
        BalancerV2Types.SingleSwap memory ss = BalancerV2Types.SingleSwap({
            poolId: pool_id_weth_rico,
            kind: BalancerV2Types.SwapKind.GIVEN_IN,  // GIVEN_IN
            assetIn: IAsset(WETH),
            assetOut: IAsset(arico),
            amount: 1 * WAD,
            userData: bytes('')
        });

        BalancerV2Types.FundManagement memory fm = BalancerV2Types.FundManagement({
            sender: me,
            fromInternalBalance: false,
            recipient: payable(me),
            toInternalBalance: false
        });

        uint toklimit = WAD / 10;
        uint wethbefore = weth.balanceOf(me);
        uint ricobefore = rico.balanceOf(me);

        bvault.swap(ss, fm, toklimit, block.timestamp);

        uint wethafter = weth.balanceOf(me);
        uint ricoafter = rico.balanceOf(me);

        assertLt(wethafter, wethbefore);
        assertGt(ricoafter, ricobefore);




    }

}

