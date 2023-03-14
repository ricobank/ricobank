import '@nomiclabs/hardhat-ethers'

import './lib/gemfab/task/deploy-gemfab'
import './lib/feedbase/task/deploy-feedbase'
import './lib/weth/task/deploy-mock-weth'
import './lib/uniswapv3/task/deploy-uniswapv3'

import './task/deploy-mock-gemfab'
import './task/deploy-mock-feedbase'

import './task/deploy-mock-dependencies'
import './task/deploy-ricobank'

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    version: "0.8.19",
    settings: {
      outputSelection: {
        "*": {
          "*": ["storageLayout"]
        }
      }
    }
  },
  paths: {
    sources: "./src"
  },
  networks: {
      hardhat: {
          blockGasLimit: 100000000,
          forking: {
              url: process.env["RPC_URL"],
              blockNumber: 16445606
          }
      }
  }
};
