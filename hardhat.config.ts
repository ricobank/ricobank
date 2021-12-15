import '@nomiclabs/hardhat-ethers'

import './task/deploy-mock-balancer'
import './task/deploy-balancer-pool'

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
