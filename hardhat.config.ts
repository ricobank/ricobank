import '@nomiclabs/hardhat-ethers'
import '@nomicfoundation/hardhat-verify'

import './lib/gemfab/task/deploy-gemfab'

import './task/combine-packs'
import './task/deploy-tokens'

import './task/deploy-dependencies'
import './task/deploy-ricobank'

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    compilers: [
        {
            version: "0.8.25",
            settings: {
              optimizer: {
                enabled: true,
                runs: 10000
              },
              outputSelection: {
                "*": {
                  "*": ["storageLayout"]
                }
              }
            }
        },
        {
          version: "0.8.19",
          settings: {
            optimizer: {
              enabled: true,
              runs: 20000
            }
          }
        }
    ]
  },
  paths: {
    sources: "./src"
  },
  networks: {
      hardhat: {
          forking: process.env["FORK_ARB"] ? {
            url: process.env["ARB_RPC_URL"], blockNumber: 202175244, chainId: 42161
          } : {
            url: process.env["RPC_URL"], blockNumber: 19060431, chainId: 1
          },
          accounts: {
              accountsBalance: '1000000000000000000000000000000'
          }
      },
      arbitrum_goerli: {
          url: process.env["ARB_GOERLI_RPC_URL"],
          accounts: {
            mnemonic: process.env["ARB_GOERLI_MNEMONIC"]
          },
          chainId: 421613
      },
      arbitrum_sepolia: {
          url: process.env["ARB_SEPOLIA_RPC_URL"],
          accounts: {
            mnemonic: process.env["ARB_SEPOLIA_MNEMONIC"]
          },
          chainId: 421614
      },
      sepolia: {
          url: process.env["SEPOLIA_RPC_URL"],
          accounts: {
            mnemonic: process.env["SEPOLIA_MNEMONIC"],
          },
          chainId: 11155111
      },
      arbitrum: {
        url: process.env["ARB_RPC_URL"],
        accounts: {
          mnemonic: process.env["ARB_MNEMONIC"]
        },
        chainId: 42161
      }
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      arbitrumSepolia: process.env.ARBISCAN_API_KEY
    }
  }

}
