pragma solidity 0.8.6;

interface GemLike {
    function transfer(address usr, uint amt) external;
    function balanceOf(address usr) external returns (uint);
}

interface VatLike {
  function grab(bytes32 i, address u, address v, address w, int dink, int dart) external;
  function safe(bytes32 i, address u) external returns (bool);
  function urns(bytes32 i, address u) external returns (uint, uint);
}

interface VowLike {
}

interface MultiJoinLike {
    function gem_exit(address vat, bytes32 ilk, address usr, uint wad) external;
}

interface BPool {
    function swap_exactAmountIn(address gem, uint amt) external returns (uint);
    function swap_exactAmountOut(address gem, uint amt) external returns (uint);
    function view_exactAmountOut(address gem, uint amt) external returns (uint);
}

contract Cow {
  GemLike public RICO;
  VatLike public vat;
  VowLike public vow;
  MultiJoinLike public joint;
  mapping(address=>BPool) public pools;

  function bite(bytes32 ilk, address usr) public {
    require( !vat.safe(ilk, usr), 'ERR_SAFE' );
    (uint ink, uint art) = vat.urns(ilk, usr);
    vat.grab(ilk, usr, address(this), address(vow), -int(ink), -int(art));
    joint.gem_exit(address(vat), ilk, usr, art);
  }

  function flip(address gem) public {
    uint amt = GemLike(gem).balanceOf(address(this));
    BPool pool = pools[gem];
    uint joy = pool.swap_exactAmountIn(gem, amt);
    GemLike(gem).transfer(address(vow), joy);
  }
}
