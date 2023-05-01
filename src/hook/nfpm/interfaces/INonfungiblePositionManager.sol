pragma solidity 0.8.19;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface INonfungiblePositionManager is IERC721 {
    function positions(uint256 tokenId) external view returns (
        uint96, address, address token0, address token1, uint24 fee, 
        int24 tickLower, int24 tickUpper, uint128 liquidity,
        uint256, uint256, uint128 tokensOwed0, uint128 tokensOwed1
    );
    function factory() external view returns (address);
}
