import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'
import { getDiamondArtifact } from './helpers'

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .addOptionalParam('arb', 'Arbitrum deploy')
  .addOptionalParam('writepack', 'write pack to pack dir')
  .addOptionalParam('gasLimit', 'per-tx gas limit')
  .addOptionalParam('ipfs', 'add packs to ipfs')
  .addParam('netname', 'network name to load packs from')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const ethers    = hre.ethers
    const BN        = ethers.BigNumber
    const constants = ethers.constants

    const [ali]  = await ethers.getSigners()
    const bn2b32 = (bn) => ethers.utils.hexZeroPad(bn.toHexString(), 32)

    let deps_pack
    if (args.dependencies) {
        try {
            deps_pack = JSON.parse(args.dependencies);
        } catch (e) {
            // allow deps to be passed as ipfs CID
            deps_pack = await dpack.getIpfsJson(args.dependencies);
        }
    } else {
        deps_pack = await hre.run(
          'deploy-dependencies',
          {
              mock:    args.mock,
              netname: args.netname,
              gfpackcid: args.gfpackcid,
              risk: args.risk,
              ipfs: args.ipfs
          }
        )
    }

    const deps = await dpack.load(deps_pack, ethers, ali)

    const pb = new dpack.PackBuilder(hre.network.name)

    const settings = require('./settings.json')[args.netname]

    // base diamond contract (address will be bank address)
    const diamond_artifact = require('../artifacts/src/diamond.sol/BankDiamond.json')
    const diamond_type = ethers.ContractFactory.fromSolidity(diamond_artifact, ali)
    debug('deploying diamond')
    const diamond = await diamond_type.deploy({gasLimit: args.gasLimit})

    // deployer rollup
    debug('deploying ball rollup')
    const ball_artifact = require('../artifacts/src/ball.sol/Ball.json')
    const ball_type = ethers.ContractFactory.fromSolidity(ball_artifact, ali)

    const ballargs = {
        bank: diamond.address,
        rico: deps.rico.address,
        risk: deps.risk.address,
        par:  ray(settings.par),
        wel:  ray(settings.wel),
        dam:  ray(settings.dam),
        pex:  ray(settings.pex),
        gif:  wad(settings.gif),
        mop:  ray(settings.mop),
        lax:  ray(settings.lax),
        how:  ray(settings.how),
        cap:  ray(settings.cap),
        chop: ray(settings.chop),
        dust: ray(settings.dust),
        fee:  ray(settings.fee),
        line: rad(settings.line),
        liqr: ray(settings.liqr),
    }

    debug('deploying ball...')
    const ball = await ball_type.deploy(ballargs, {gasLimit: args.gasLimit})
    debug('transferring diamond to ball')
    await send(diamond.transferOwnership, ball.address)

    debug('running ball setup...')
    await send(ball.setup, ballargs)
    debug(`done deploying ball at ${ball.address}`)

    // take diamond back
    await send(ball.approve, ali.address);

    debug('ward rico and risk')
    await send(deps.rico.ward, diamond.address, 1)
    await send(deps.risk.ward, diamond.address, 1)

    debug('accept ownership')
    await send(diamond.acceptOwnership)

    debug('creating pack')
    const getartifact = async (ty) => {
        debug(`getting artifact for ${ty}`)
        return dpack.getIpfsJson(deps.types[ty].artifact['/']);
    }

    debug('packing ball')
    await pb.packObject({
        objectname: 'ball',
        address: ball.address,
        typename: 'Ball',
        artifact: require('../artifacts/src/ball.sol/Ball.json')
    })

    debug('packing Ricobank diamond')

    await pb.packObject({
        objectname: 'bank',
        address: diamond.address,
        typename: 'BankDiamond',
        artifact: getDiamondArtifact()
    }, true)
    debug('all packed, merging')

    const pack = (await pb.merge(deps_pack)).build()
    if (args.writepack) {
        const outfile = require('path').join(
            __dirname, `../pack/ricobank_${hre.network.name}.dpack.json`
        )
        const packstr = JSON.stringify(pack, null, 2)
        require('fs').writeFileSync(outfile, packstr)
    }

    if (args.ipfs) {
      console.log("deploy-ricobank IPFS CIDs:")
      let cid = await dpack.putIpfsJson(deps_pack, true)
      console.log(`  Dependencies: ${cid}`)
      cid = await dpack.putIpfsJson(pack, true)
      console.log(`  Ricobank: ${cid}`)
    }

    return pack
  })
