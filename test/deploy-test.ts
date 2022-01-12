const debug = require('debug')('ricobank:test')

import { want } from 'minihat'
const hh = require('hardhat')

describe('deploy-ricobank task', ()=>{
  it('deploy', async() => {
    debug(Object.keys(hh))
    debug(Object.keys(hh.network))
    debug(hh.network.name)
    const pack = await hh.run('deploy-ricobank', {mock:'true'});
    want(pack.objects.vat).exists
  })
})
