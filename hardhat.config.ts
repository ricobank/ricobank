import '@nomiclabs/hardhat-ethers'

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: "0.8.9",
  paths: {
    sources: "./sol"
  },
  defaultNetwork: 'hardhat'
};
