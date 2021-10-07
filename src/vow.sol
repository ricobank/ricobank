// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.6;

interface VatLike {
  function dai() external returns (uint);
  function vice() external returns (uint);
  function heal(uint amt) external;
  function drip(bytes32 ilk) external;
}

interface BPool {
    function swap_exactAmountIn(address gem, uint amt) external returns (uint);
    function swap_exactAmountOut(address gem, uint amt) external returns (uint);
    function view_exactAmountOut(address gem, uint amt) external returns (uint);
}

interface DaiJoin {
    function exit(uint amt) external;
    function join(uint amt) external;
}

interface GemLike {
    function mint(address usr, uint amt) external;
    function burn(address usr, uint amt) external;
    function approve(address usr, uint amt) external;
    function balanceOf(address usr) external returns (uint);
}

contract Vow {
    VatLike public vat;
    DaiJoin public daijoin;
    GemLike public RICO;
    GemLike public BANK;
    BPool public pool;

    function drip(bytes32[] calldata ilks) public {
        for(uint i = 0; i < ilks.length; i++) {
            vat.drip(ilks[i]);
        }
        uint dai = vat.dai();
        daijoin.exit(dai);
    }

    // sell surplus rico for bank, burn bank
    function flap() public {
        uint rico = RICO.balanceOf(address(this));
        uint bank = pool.swap_exactAmountIn(address(RICO), rico);
        BANK.burn(address(this), bank);
    }

    function flop() public {
        uint vice = vat.vice();
        uint need = pool.view_exactAmountOut(address(RICO), vice);
        BANK.mint(address(this), need);
        pool.swap_exactAmountOut(address(RICO), vice);
        daijoin.join(vice);
        vat.heal(vice);
    }

    function reapprove() public {
        RICO.approve(address(daijoin), type(uint256).max);
        RICO.approve(address(pool), type(uint256).max);
        BANK.approve(address(pool), type(uint256).max);
    }
}



