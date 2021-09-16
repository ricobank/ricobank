pragma solidity 0.8.6;

contract Ward {
    mapping (address => bool) public wards;
    function rely(address usr) external auth {
      wards[usr] = true;
    }
    function deny(address usr) external auth {
      wards[usr] = false;
    }
    function ward() internal view {
      require(wards[msg.sender], 'err-ward');
    }
    modifier auth { 
      ward();
      _;
    }
}
