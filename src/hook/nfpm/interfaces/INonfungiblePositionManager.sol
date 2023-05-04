pragma solidity >=0.7.0;

//import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface IERC721 {
    function transfer(address, uint) external;
    function transferFrom(address, address, uint) external;
    function approve(address, uint) external;
}
interface INonfungiblePositionManager is IERC721 {
    function positions(uint256 tokenId) external view returns (
        uint96, address, address token0, address token1, uint24 fee, 
        int24 tickLower, int24 tickUpper, uint128 liquidity,
        uint256, uint256, uint128 tokensOwed0, uint128 tokensOwed1
    );
    function factory() external view returns (address);
}
