import { task } from 'hardhat/config'

task('deploy-mock-weth', '')
.setAction(async (args, hre) => {
  return await hre.run('deploy-mock-weth9')
})
