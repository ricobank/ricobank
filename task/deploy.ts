const debug = require('debug')('rico:deploy')

const dpack = require('dpack')

const { task, subtask } = require('hardhat/config')

async function deploySingleton(hre: any, name : string, mutator : any) : Promise<any> {
    const network = hre.network.name;
    const artifact = await hre.artifacts.readArtifact(name)
    const deployer = await hre.ethers.getContractFactory(name)
    const obj = await deployer.deploy();
    await obj.deployed();
    await mutator.addType(artifact);
    await mutator.addObject(name, obj.address, network, artifact);
    console.log(`${name} deployed to: `, obj.address);
    return Promise.resolve(obj);
}

task('deploy-autobank', 'initial system deployment')
.addParam('dpack', 'autobank dpack path to save output')
.setAction(async (args, hre) => {
  const { ethers, network } = hre;

  const [acct] = await hre.ethers.getSigners();
  console.log(`Deploying from address ${acct.address} to network ${network.name}`)

  await dpack.initPackFile(args.dpack);
  await dpack.mutatePackFile(args.dpack, args.dpack, async (mutator) => {

    // feedbase
    // gemfab
    // bfactory
    // rico = gemfab.build()
    // bank = gemfab.build()
    // pool = bfactory.build()
    const vat = await deploySingleton(hre, 'Vat', mutator);
    const vox = await deploySingleton(hre, 'Vox', mutator);
    const vow = await deploySingleton(hre, 'Vow', mutator);
//    const daijoin = await deploySingleton(hre, 'DaiJoin', mutator);
    const multijoin = await deploySingleton(hre, 'GemMultiJoin', mutator);
    const plotter = await deploySingleton(hre, 'Plotter', mutator);

    // vat.rely(vox)
    // vat.rely(vow)
    // vat.rely(daijoin)
    // vat.rely(multijoin)
    // vat.rely(plotter)

  });

  console.log('Done!')
  
})

export {}
