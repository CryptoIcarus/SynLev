const uniV2StakingArtifacts = artifacts.require('uniV2Staking')
const erc20Artifacts = artifacts.require('IERC20')
const synStakingArtifacts = artifacts.require('synStaking')

// To run this test:
// In 1 terminal:
//   ganache-cli -g 0 --account 0x42fa44160d468f9ed88c59aff4bd17845c046f519aef9b9123027a4b1731afb9,100000000000000000000000000 --unlock 0x41bc7d0687e6cea57fa26da78379dfdc5627c56d --unlock 0xa2E316CbfA81640ce509ab487867a136b75C83C4 --unlock 0xf000000000000000000000000000000000000000 --fork $YOUR_INFURA_API_URL
// In another terminal:
//   truffle test
// This test file makes changes to the ganache fork that persist across runs of the test.
// This means every time you want to re-run the test file, just rerun the `ganache-cli` command above.

// Some random address that is currently an UNI LP to use for moving UNI LP tokens around
const uniV2TestAddress = '0x41bc7d0687e6cea57fa26da78379dfdc5627c56d'
// SynLev deployer with a ton of SYN to use for moving SYN around in tests
const synTestAddress = '0xa2E316CbfA81640ce509ab487867a136b75C83C4'
// Just some random addy
const fooAddress = '0xf000000000000000000000000000000000000000'
// Mainnet address of the synStaking contract
const synStakingAddress = '0xf21c4F3a748F38A0B244f649d19FdcC55678F576'
// Address of SYN
const synTokenAddress = '0x1695936d6a953df699C38CA21c2140d497C08BD9'
// Address of the SYN-ETH UNI v2 pair/LP token
const uniV2TokenAddress = '0xdF27A38946a1AcE50601Ef4e10f07A9CC90d7231'
// Has a lot of eth used for moving eth around
const testAddress = '0x5026250def50163673fA0b8f8c58979E9BCfc124'

function assertIsEqualWithTolerance(aBN, bBN, tolerance) {
	const toleranceBN = web3.utils.toBN(tolerance)
	assert(
		// a <= b + tolerance && a >= b - tolerance
		(aBN.lte(bBN.add(toleranceBN)) && aBN.gte(bBN.sub(toleranceBN))) ||
		// b <= a + tolerance && b >= a - tolerance
		(bBN.lte(aBN.add(toleranceBN)) && bBN.gte(aBN.sub(toleranceBN)))
	)
}

contract('uniV2Staking', accounts => {
	let uniV2Staking;
	let synStaking;
	let synToken;
	let uniV2Token;

	before(async () => {
		synStaking = await synStakingArtifacts.at(synStakingAddress)
		synToken = await erc20Artifacts.at(synTokenAddress)
		uniV2Token = await erc20Artifacts.at(uniV2TokenAddress)
	})

	beforeEach(async () => {
		uniV2Staking = await uniV2StakingArtifacts.deployed()
	})

  it('should allow syn to be staked and unstaked via the contract', async () => {
		// First, let's have synTestAddress stake some
		const synStakeAmount = web3.utils.toBN(6942000000000000000)
		// approve syn to be transferred to the uniV2Staking contract
		await synToken.approve(uniV2Staking.address, synStakeAmount, { from: synTestAddress })
		await uniV2Staking.stakeSyn(synStakeAmount, { from: synTestAddress })
		assert.equal(
			(await uniV2Staking.stakedSyn(synTestAddress)).toString(),
			synStakeAmount.toString()
		)
		// Check total syn staked by the uniV2Staking contract
		const { syn: uniV2StakingTotalSynStaked } = await synStaking.userStake(uniV2Staking.address)
		assert.equal(
			uniV2StakingTotalSynStaked.toString(),
			synStakeAmount.toString()
		)

		// Second, let's have fooAddress stake some
		const fooSynStakeAmount = web3.utils.toBN(4206900000000000000)
		// send the syn from synlev deployer to fooAddress
		await synToken.transfer(fooAddress, fooSynStakeAmount, { from: synTestAddress })
		assert.equal(
			(await synToken.balanceOf(fooAddress)).toString(),
			fooSynStakeAmount.toString()
		)
		// approve syn to be transferred to the uniV2Staking contract
		await synToken.approve(uniV2Staking.address, fooSynStakeAmount, { from: fooAddress, gasPrice: 0 })
		await uniV2Staking.stakeSyn(fooSynStakeAmount, { from: fooAddress, gasPrice: 0 })
		assert.equal(
			(await uniV2Staking.stakedSyn(fooAddress)).toString(),
			fooSynStakeAmount.toString()
		)
		// Check total syn staked by the uniV2Staking contract
		const { syn: uniV2StakingTotalSynStakedAfterFoo } = await synStaking.userStake(uniV2Staking.address)
		assert.equal(
			uniV2StakingTotalSynStakedAfterFoo.toString(),
			synStakeAmount.add(fooSynStakeAmount).toString()
		)

		// Now let's have fooAddress unstake a portion of their SYN
		const fooSynUnstakeAmount = web3.utils.toBN(6900000000000000)
		await uniV2Staking.unstakeSyn(fooSynUnstakeAmount, { from: fooAddress, gasPrice: 0 })
		assert.equal(
			(await uniV2Staking.stakedSyn(fooAddress)).toString(),
			fooSynStakeAmount.sub(fooSynUnstakeAmount).toString()
		)
		assert.equal(
			(await synToken.balanceOf(fooAddress)).toString(),
			fooSynUnstakeAmount.toString()
		)
		const { syn: uniV2StakingTotalSynStakedAfterFooUnstakedSome } = await synStaking.userStake(uniV2Staking.address)
		assert.equal(
			uniV2StakingTotalSynStakedAfterFooUnstakedSome.toString(),
			synStakeAmount.add(fooSynStakeAmount).sub(fooSynUnstakeAmount).toString()
		)

		// and now let's have fooAddress unstake the rest of their SYN
		const fooSynRemainingUnstakeAmount = fooSynStakeAmount.sub(fooSynUnstakeAmount)
		await uniV2Staking.unstakeSyn(fooSynRemainingUnstakeAmount, { from: fooAddress, gasPrice: 0 })
		assert.equal(
			(await uniV2Staking.stakedSyn(fooAddress)).toString(),
			'0'
		)
		assert.equal(
			(await synToken.balanceOf(fooAddress)).toString(),
			fooSynStakeAmount.toString() // the initial amount of syn they had
		)
		const { syn: uniV2StakingTotalSynStakedAfterFooUnstakedAll } = await synStaking.userStake(uniV2Staking.address)
		assert.equal(
			uniV2StakingTotalSynStakedAfterFooUnstakedAll.toString(),
			synStakeAmount.toString()
		)

		// and let's have our OG address unstake all of theirs too
		await uniV2Staking.unstakeSyn(synStakeAmount, { from: synTestAddress, gasPrice: 0 })
		assert.equal(
			(await uniV2Staking.stakedSyn(synTestAddress)).toString(),
			'0'
		)
		const { syn: uniV2StakingTotalSynStakedAfterAllUnstakedAll } = await synStaking.userStake(uniV2Staking.address)
		assert.equal(
			uniV2StakingTotalSynStakedAfterAllUnstakedAll.toString(),
			'0'
		)
	})

	it('should allow SYN-ETH LP tokens to be staked and unstaked and distribute rewards accordingly', async () => {

		// First, let's have uniV2TestAddress stake some
		const uniV2StakeAmount = web3.utils.toBN(6942000000000000000)
		// approve uniV2 to be transferred to the uniV2Staking contract
		await uniV2Token.approve(uniV2Staking.address, uniV2StakeAmount, { from: uniV2TestAddress })
		await uniV2Staking.stake(uniV2StakeAmount, { from: uniV2TestAddress })
		const { uniV2Tokens: uniV2TokensStaked } = await uniV2Staking.userStake(uniV2TestAddress)
		assert.equal(
			uniV2TokensStaked.toString(),
			uniV2StakeAmount.toString()
		)

		// Second, let's have fooAddress stake some
		const fooUniV2StakeAmount = web3.utils.toBN(4206900000000000000)
		// send the uniV2 from uniV2lev deployer to fooAddress
		await uniV2Token.transfer(fooAddress, fooUniV2StakeAmount, { from: uniV2TestAddress })
		assert.equal(
			(await uniV2Token.balanceOf(fooAddress)).toString(),
			fooUniV2StakeAmount.toString()
		)
		// approve uniV2 to be transferred to the uniV2Staking contract
		await uniV2Token.approve(uniV2Staking.address, fooUniV2StakeAmount, { from: fooAddress, gasPrice: 0 })
		await uniV2Staking.stake(fooUniV2StakeAmount, { from: fooAddress, gasPrice: 0 })
		const { uniV2Tokens: uniV2TokensStakedAfterFoo } = await uniV2Staking.userStake(fooAddress)
		assert.equal(
			uniV2TokensStakedAfterFoo.toString(),
			fooUniV2StakeAmount.toString()
		)
		// Check total uniV2 staked
		assert.equal(
			(await uniV2Staking.uniV2TotalStaked()).toString(),
			uniV2StakeAmount.add(fooUniV2StakeAmount).toString()
		)

		const oneEth = web3.utils.toBN(web3.utils.toWei('1'))

		// Let's now give 1 eth to the uniV2Staking contract
		web3.eth.sendTransaction({
			from: '0x5026250def50163673fA0b8f8c58979E9BCfc124',
			to: uniV2Staking.address,
			value: oneEth
		})

		// Now let's have fooAddress unstake a portion
		const fooUniV2UnstakeAmount = web3.utils.toBN(6900000000000000)
		await uniV2Staking.unstake(fooUniV2UnstakeAmount, { from: fooAddress, gasPrice: 0 })
		const { uniV2Tokens: uniV2TokensStakedAfterFooUnstakedSome } = await uniV2Staking.userStake(fooAddress)
		assert.equal(
			uniV2TokensStakedAfterFooUnstakedSome.toString(),
			fooUniV2StakeAmount.sub(fooUniV2UnstakeAmount).toString()
		)
		assert.equal(
			(await uniV2Token.balanceOf(fooAddress)).toString(),
			fooUniV2UnstakeAmount.toString()
		)
		assert.equal(
			(await uniV2Staking.uniV2TotalStaked()).toString(),
			uniV2StakeAmount.add(fooUniV2StakeAmount).sub(fooUniV2UnstakeAmount).toString()
		)
		const fooEthBalanceAfterUnstakingSome = web3.utils.toBN(await web3.eth.getBalance(fooAddress))
		// We expect fooAddress to receive (fooUniV2UnstakeAmount / totalAmountStaked) of the 1 eth.
		// This is because we get the reward for all the uniV2 staked by fooAddress, not just
		// what was unstaked
		assertIsEqualWithTolerance(
			fooEthBalanceAfterUnstakingSome,
			fooUniV2StakeAmount.mul(oneEth).div(uniV2StakeAmount.add(fooUniV2StakeAmount)),
			3 // few wei tolerance to deal with integer division
		)

		// Let's give another 1 eth
		web3.eth.sendTransaction({
			from: '0x5026250def50163673fA0b8f8c58979E9BCfc124',
			to: uniV2Staking.address,
			value: oneEth
		})

		// and now let's have fooAddress unstake the rest of their SYN
		const fooUniV2RemainingUnstakeAmount = fooUniV2StakeAmount.sub(fooUniV2UnstakeAmount)
		await uniV2Staking.unstake(fooUniV2RemainingUnstakeAmount, { from: fooAddress, gasPrice: 0 })
		const { uniV2Tokens: uniV2TokensStakedAfterFooUnstakedAll } = await uniV2Staking.userStake(fooAddress)
		assert.equal(
			uniV2TokensStakedAfterFooUnstakedAll.toString(),
			'0'
		)
		assert.equal(
			(await uniV2Token.balanceOf(fooAddress)).toString(),
			fooUniV2StakeAmount.toString() // the initial amount of uniV2 they had
		)
		assert.equal(
			(await uniV2Staking.uniV2TotalStaked()).toString(),
			uniV2StakeAmount.toString()
		)

		assertIsEqualWithTolerance(
			web3.utils.toBN(await web3.eth.getBalance(fooAddress)).sub(fooEthBalanceAfterUnstakingSome),
			// For the new 1 eth that was given to the contract after we unstaked some
			fooUniV2RemainingUnstakeAmount.mul(oneEth).div(uniV2StakeAmount.add(fooUniV2RemainingUnstakeAmount)),
			3 // few wei tolerance to deal with integer division
		)

		const uniV2TestAddressBalanceBeforeUnstaking = web3.utils.toBN(await web3.eth.getBalance(uniV2TestAddress))
		// and let's have our OG address unstake all of theirs too
		await uniV2Staking.unstake(uniV2StakeAmount, { from: uniV2TestAddress, gasPrice: 0 })
		const { uniV2Tokens: uniV2TokensStakedAfterAllUnstaked } = await uniV2Staking.userStake(uniV2TestAddress)
		assert.equal(
			uniV2TokensStakedAfterAllUnstaked.toString(),
			'0'
		)
		assert.equal(
			(await uniV2Staking.uniV2TotalStaked()).toString(),
			'0'
		)

		assertIsEqualWithTolerance(
			web3.utils.toBN(await web3.eth.getBalance(uniV2TestAddress)).sub(uniV2TestAddressBalanceBeforeUnstaking),
			// The first eth...
			uniV2StakeAmount
				.mul(oneEth)
				.div(uniV2StakeAmount.add(fooUniV2StakeAmount))
			// the second eth...
				.add(
					uniV2StakeAmount
						.mul(oneEth)
						.div(uniV2StakeAmount.add(fooUniV2RemainingUnstakeAmount))
				),
			3 // few wei tolerance to deal with integer division
		)
	})
})