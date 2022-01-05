// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import '../mixin/math.sol';
import '../swap.sol';
import '../abi.sol';

contract MockFlowerPlopper is Math, BalancerSwapper, Flipper
{
    struct Auction {
        bytes32 ilk;
        address urn;
        address gem;
        uint ink;
        uint bill;
    }
    address public RICO;
    address public vow;
    mapping (uint => Auction) public auctions;
    uint public counter;

    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external {
        uint id = ++counter;
        auctions[id].ilk = ilk;
        auctions[id].urn = urn;
        auctions[id].gem = gem;
        auctions[id].ink = ink;
        auctions[id].bill = bill;
    }

    function complete_auction(uint id) external {
        uint spill = _trade(auctions[id].gem, RICO, SwapKind.GIVEN_OUT, auctions[id].bill);
        uint refund = auctions[id].ink - spill;
        GemLike(auctions[id].gem).transfer(vow, refund);
        Plopper(vow).plop(auctions[id].ilk, auctions[id].urn, refund);
        delete auctions[id];
    }

    function _trade(address tokIn, address tokOut, SwapKind kind, uint amt) internal returns (uint256) {
        SingleSwap memory ss = SingleSwap({
            poolId: pools[tokIn][tokOut],
            kind: kind,
            assetIn: IAsset(tokIn),
            assetOut: IAsset(tokOut),
            amount: amt,
            userData: ""
        });
        FundManagement memory fm = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(vow),
            toInternalBalance: false
        });
        return bvault.swap(ss, fm, type(uint256).max, block.timestamp);
    }

    function approve_gem(address gem) external {
        GemLike(gem).approve(address(bvault), type(uint256).max);
        GemLike(gem).approve(vow, type(uint256).max);
    }

    function file(bytes32 key, address val)
      _ward_ external {
        if (key == "rico") {RICO = val;
        } else if (key == "vow") {vow = val;
        } else {revert("ERR_FILE_KEY");}
    }
}
