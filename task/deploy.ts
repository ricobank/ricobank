const debug = require('debug')('rico:deploy')

const { task, subtask } = require('hardhat/config')

async function deploySingleton (hre: any, name: string): Promise<any> {
  const network = hre.network.name
  const artifact = await hre.artifacts.readArtifact(name)
  const deployer = await hre.ethers.getContractFactory(name)
  const obj = await deployer.deploy()
  await obj.deployed()
  console.log(`${name} deployed to: `, obj.address)
  return await Promise.resolve(obj)
}

task('deploy-autobank', 'initial system deployment')
  .setAction(async (args, hre) => {
    const { ethers, network } = hre

    const [acct] = await hre.ethers.getSigners()
    console.log(`Deploying from address ${acct.address} to network ${network.name}`)

    // feedbase
    // gemfab
    // bfactory
    // rico = gemfab.build()
    // bank = gemfab.build()
    // pool = bfactory.build()
    const vat = await deploySingleton(hre, 'Vat')
    const vox = await deploySingleton(hre, 'Vox')
    const vow = await deploySingleton(hre, 'Vow')
    //    const daijoin = await deploySingleton(hre, 'DaiJoin', mutator);
    const multijoin = await deploySingleton(hre, 'GemMultiJoin')
    const plotter = await deploySingleton(hre, 'Plotter')

    // vat.rely(vox)
    // vat.rely(vow)
    // vat.rely(daijoin)
    // vat.rely(multijoin)
    // vat.rely(plotter)

    console.log('Done!')
  })

export {}
