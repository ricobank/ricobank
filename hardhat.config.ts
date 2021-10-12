import '@nomiclabs/hardhat-ethers'

import './task/deploy'

const { PRIVKEY, INFURA_PROJECT_ID } = process.env

const privKey = PRIVKEY ?? Buffer.alloc(32).toString('hex')


/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: "0.8.9",
  paths: {
    sources: "./src"
  },
  defaultNetwork: 'hardhat',
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_PROJECT_ID}`,
      chainId: 1,
      accounts: [`0x${privKey}`]
    },
    ropsten: {
      url: `https://ropsten.infura.io/v3/${INFURA_PROJECT_ID}`,
      chainId: 3,
      accounts: [`0x${privKey}`]
    },
  }
};
