import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .addOptionalParam('arb', 'Arbitrum deploy')
  .addOptionalParam('tokens', 'JSON file with token addresses')
  .addOptionalParam('writepack', 'write pack to pack dir')
  .addOptionalParam('gasLimit', 'per-tx gas limit')
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
        deps_pack = require(args.dependencies)
    } else {
        deps_pack = await hre.run(
          'deploy-mock-dependencies',
          { 
              tokens:  args.tokens,
              netname: args.netname,
              mock:    args.mock
          }
        )
    }

    const deps = await dpack.load(deps_pack, ethers, ali)

    const pb = new dpack.PackBuilder(hre.network.name)

    const fb     = deps.feedbase;
    const tokens = args.tokens ? require(args.tokens)[args.netname] : {}
    let agg_daiusd, agg_xauusd, agg_artifact, agg_type
    let aggdapp
    if (args.mock) {
        // deploy a fake aggregator that we can easily write to
        agg_artifact = require('../lib/feedbase/artifacts/src/test/MockChainlinkAggregator.sol/MockChainlinkAggregator.json')
        agg_type     = ethers.ContractFactory.fromSolidity(agg_artifact, ali)

        agg_daiusd   = await agg_type.deploy(
            fb.address, ali.address, b32('dai:usd'), 8, {gasLimit: args.gasLimit}
        )
        agg_xauusd   = await agg_type.deploy(
            fb.address, ali.address, b32('xau:usd'), 8,
            {gasLimit: args.gasLimit}
        )
        await send(fb.push, b32('dai:usd'), bn2b32(BN.from('100000000')), constants.MaxUint256);
        await send(fb.push, b32('xau:usd'), bn2b32(BN.from('190000000000')), constants.MaxUint256);


    } else {
        const aggpack = require(`../lib/chainlink/pack/chainlink_${args.netname}.dpack.json`)
        await pb.merge(aggpack)

        aggdapp    = await dpack.load(aggpack, ethers, ali)
        agg_daiusd = aggdapp.dai_usd
        agg_xauusd = aggdapp.xau_usd
    }


    // base diamond contract (address will be bank address)
    const diamond_artifact = require('../artifacts/src/diamond.sol/BankDiamond.json')
    const diamond_type = ethers.ContractFactory.fromSolidity(diamond_artifact, ali)
    debug('deploying diamond')
    const diamond = await diamond_type.deploy({gasLimit: args.gasLimit})

    // deployer rollup
    debug('deploying ball rollup')
    const ball_artifact = require('../artifacts/src/ball.sol/Ball.json')
    const ball_type = ethers.ContractFactory.fromSolidity(ball_artifact, ali)

    debug('deploying erc20 hook')
    const tokhook_artifact = require('../artifacts/src/hook/erc20/ERC20Hook.sol/ERC20Hook.json')
    const tokhook_type = ethers.ContractFactory.fromSolidity(tokhook_artifact, ali)
    const tokhook = await tokhook_type.deploy({gasLimit: args.gasLimit})

    debug('deploying uni hook')
    const unihook_artifact = require('../artifacts/src/hook/nfpm/UniV3NFTHook.sol/UniNFTHook.json')
    const unihook_type = ethers.ContractFactory.fromSolidity(unihook_artifact, ali)
    const unihook = await unihook_type.deploy(
      deps.nonfungiblePositionManager.address, {gasLimit: args.gasLimit}
    )

    const ups = {
        ilk: b32(':uninft'),
        fee: BN.from("1000000001546067052200000000"),
        chop: ray(1),
        dust: rad(0.1),
        line: rad(10000),
        room: 8,
        uniwrapper: deps.uniwrapper.address
    }

    const ballargs = {
        bank: diamond.address,
        feedbase: fb.address,
        uniadapt: deps.uniswapv3adapter.address,
        divider: deps.divider.address,
        multiplier: deps.multiplier.address,
        cladapt: deps.chainlinkadapter.address,
        tokhook: tokhook.address,
        unihook: unihook.address,
        rico: deps.rico.address,
        risk: deps.risk.address,
        ricodai: deps.ricodai.address,
        ricorisk: deps.ricorisk.address,
        dai: deps.dai.address,
        dai_usd_agg: agg_daiusd.address,
        xau_usd_agg: agg_xauusd.address,
        par: ray(1),
        ceil: wad(100000),
        adaptrange: 1,
        adaptttl:   BANKYEAR / 4,
        daiusdttl:  BANKYEAR,
        xauusdttl:  BANKYEAR,
        twaprange:  500,
        twapttl:    BANKYEAR,
        platpep:    2,
        platpop:    ray(1),
        plotpep:    2,
        plotpop:    ray(1),
        mintramp:   {
            bel: (await ethers.provider.getBlock('latest')).timestamp,
            cel: 1,
            rel: ray(0.02).div(BANKYEAR),
            wel: ray(1) 
        },
    }

    let ilks   = []
    for (let token in tokens) {
        const params = tokens[token];  
        let ilk = {
            ilk: b32(params.ilk),
            gem: deps[token].address,
            gemusdagg: constants.AddressZero,
            gemethagg: constants.AddressZero,
            chop: ray(params.chop),
            dust: rad(params.dust),
            fee:  ray(params.fee),
            line: rad(params.line),
            liqr: ray(params.liqr),
            ttl: params.ttl,
            range: params.range
        }


        if (args.mock) {
            // create mock chainlink feed with price of 2000
            const val = bn2b32(BN.from('200000000000'))
            await send(fb.push, b32(token + ':usd'), val, constants.MaxUint256);

            debug('deploying mock aggregator for token', token)
            const agg_tokenusd = await agg_type.deploy(
                fb.address, ali.address, b32(token + ':usd'), 8,
                {gasLimit: args.gasLimit}
            )

            ilk.gemusdagg = agg_tokenusd.address;
        } else {
            const gemethagg = aggdapp[`agg_${token}_eth`]
            const gemusdagg = aggdapp[`agg_${token}_usd`]
            ilk.gemusdagg = gemusdagg ? gemusdagg.address : constants.AddressZero
            ilk.gemethagg = gemethagg ? gemethagg.address : constants.AddressZero
        }

        ilks.push(ilk)
    }

    debug('deploying ball...')
    const ball = await ball_type.deploy(ballargs, {gasLimit: args.gasLimit})
    debug('transferring diamond to ball')
    await send(diamond.transferOwnership, ball.address)
    debug('add ball as ward in fb components')
    await send(deps.uniswapv3adapter.ward, ball.address, true)
    await send(deps.divider.ward, ball.address, true)
    await send(deps.multiplier.ward, ball.address, true)
    await send(deps.chainlinkadapter.ward, ball.address, true)

    debug('running ball setup...')
    await send(ball.setup, ballargs)
    debug(`done deploying ball at ${ball.address}...making ilks`)
    for (let ilk of ilks) {
        debug("making ilk: ", ilk)
        await send(ball.makeilk, ilk)
    }
    debug(`done making ilks...making uni hook`)
    await send(ball.makeuni, ups);
    await send(ball.approve, ali.address);
    debug('done making uni hook')
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
    let top_artifact = require('../artifacts/hardhat-diamond-abi/HardhatDiamondABI.sol/BankDiamond.json')
    top_artifact.deployedBytecode = diamond_artifact.deployedBytecode
    top_artifact.bytecode = diamond_artifact.bytecode
    top_artifact.linkReferences = diamond_artifact.linkReferences
    top_artifact.deployedLinkReferences = diamond_artifact.deployedLinkReferences
    top_artifact.abi = top_artifact.abi.filter((item, idx) => {
        return top_artifact.abi.findIndex(a => item.name == a.name) == idx
    })

    await pb.packObject({
        objectname: 'bank',
        address: diamond.address,
        typename: 'Ricobank',
        artifact: top_artifact
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
    return pack
  })
