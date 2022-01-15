import '@nomiclabs/hardhat-ethers'

import './lib/gemfab/task/deploy-gemfab'
import './lib/feedbase/task/deploy-feedbase'
import './lib/weth-pack/task/deploy-mock-weth9'
import './lib/balancer-pack/task/deploy-mock-balancer'

import './task/deploy-mock-gemfab'
import './task/deploy-mock-feedbase'
import './task/build-weighted-bpool'

import './task/deploy-mock-dependencies'
import './task/deploy-ricobank'

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
