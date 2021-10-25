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
  }
};
