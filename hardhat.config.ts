import '@nomiclabs/hardhat-ethers'

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    version: "0.8.9",
    settings: {
      outputSelection: {
        "*": {
          "*": ["storageLayout"]
        }
      }
    }
  },
  paths: {
    sources: "./sol"
  },
  defaultNetwork: 'hardhat'
};
