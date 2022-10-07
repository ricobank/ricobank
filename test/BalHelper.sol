// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ball } from '../src/ball.sol';

interface WeightedPoolFactoryLike {
    function create(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}

interface Pool {
    function getPoolId() external view returns (bytes32);
}

interface VaultLike {
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );
}

struct Asset {
    address token;
    uint256 weight;
    uint256 amountIn;
}

struct PoolArgs {
    Asset a1;
    Asset a2;
    string name;
    string symbol;
    uint256 swapFeePercentage;
}

abstract contract BalSetUp {
    address constant BAL_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant BAL_W_P_F = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;
    VaultLike vault = VaultLike(BAL_VAULT);
    WeightedPoolFactoryLike wpf = WeightedPoolFactoryLike(BAL_W_P_F);
    enum JoinKind { INIT, EXACT_TOKENS_IN_FOR_BPT_OUT, TOKEN_IN_FOR_EXACT_BPT_OUT }

    function create_and_join_pool(PoolArgs memory args) public returns(bytes32) {
        Asset memory a;
        Asset memory b;
        VaultLike.JoinPoolRequest memory req;
        bytes32 pool_id;

        if (args.a1.token < args.a2.token){
            a = args.a1;
            b = args.a2;
        } else {
            a = args.a2;
            b = args.a1;
        }

        address[] memory tokens  = new address[](2);
        tokens[0] = a.token;
        tokens[1] = b.token;
        uint256[] memory weights = new uint256[](2);
        weights[0] = a.weight;
        weights[1] = b.weight;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a.amountIn;
        amounts[1] = b.amountIn;
        address pool = wpf.create(args.name, args.symbol, tokens, weights,
                                  args.swapFeePercentage, address(this));

        bytes memory user_data = abi.encode(JoinKind.INIT, amounts);
        req = VaultLike.JoinPoolRequest(tokens, amounts, user_data, false);
        pool_id = Pool(pool).getPoolId();
        vault.joinPool(pool_id, address(this), address(this), req);
        return pool_id;
    }

    function join_pool(PoolArgs memory args, bytes32 pool_id) public {
        Asset memory a;
        Asset memory b;
        VaultLike.JoinPoolRequest memory req;

        if (args.a1.token < args.a2.token){
            a = args.a1;
            b = args.a2;
        } else {
            a = args.a2;
            b = args.a1;
        }

        address[] memory tokens  = new address[](2);
        tokens[0] = a.token;
        tokens[1] = b.token;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a.amountIn;
        amounts[1] = b.amountIn;
        bytes memory user_data = abi.encode(JoinKind.INIT, amounts);
        req = VaultLike.JoinPoolRequest(tokens, amounts, user_data, false);
        vault.joinPool(pool_id, address(this), address(this), req);
    }
}
