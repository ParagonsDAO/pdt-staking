
const { ethers } = require("hardhat");
const { expect } = require("chai");


describe('Brand Token', () => {

    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const TEN_MILLION = "10000000000000000000000000";
    const HUNDRED_MILLION = "100000000000000000000000000";
    const ONE_THOUSAND = "1000000000000000000000";
    const TWO_THOUSAND = "2000000000000000000000";
    const FIVE_THOUSAND = "5000000000000000000000";
    const ONE_DAY = "86400";
    const TWO_DAYS = "172800";
    const THIRTY_DAYS = "2592000";

    let
      // Used as default deployer for contracts, asks as owner of contracts.
      deployer, 
      user,
      user2,
      ERC20Factory,
      pdt,
      payout,
      Staking,
      staking

    beforeEach(async () => {

        [deployer, user, user2] = await ethers.getSigners();

        ERC20Factory = await ethers.getContractFactory('MockERC20');

        pdt = await ERC20Factory.deploy();
        payout = await ERC20Factory.deploy();

        Staking = await ethers.getContractFactory('PDTStaking');
        staking = await Staking.deploy(THIRTY_DAYS, ONE_DAY, pdt.address, payout.address);

        await pdt.mint(deployer.address, TEN_MILLION);
        await pdt.mint(user.address, TEN_MILLION);

        await payout.mint(deployer.address, TEN_MILLION);

        await pdt.approve(staking.address, TEN_MILLION);
        await pdt.connect(user).approve(staking.address, TEN_MILLION);
    });

    describe('constructor()', () => {
        it('should set epoch length correctly', async () => {
            expect(await staking.epochLength()).to.equal(ONE_DAY);
        });

        it('should set time to double correctly', async () => {
            expect(await staking.timeToDouble()).to.equal(THIRTY_DAYS);
        });

        it('should set pdt token correctly', async () => {
            expect(await staking.pdt()).to.equal(pdt.address);
        });

        it('should set payout token correctly', async () => {
            expect(await staking.rewardToken()).to.equal(payout.address);
        });
    });

    describe('distribute()', () => {
        it('should begin first epoch properly', async () => {
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.distirbute();

            let epoch = await staking.currentEpoch();

            console.log(epoch);

            expect(epoch[0]).to.equal(FIVE_THOUSAND);
            expect(epoch[1]).to.equal('0');
            expect(epoch[3] - epoch[2]).to.equal(86400);
            expect(epoch[4]).to.equal('0');
            expect(epoch[5]).to.equal('0');
        });

        it('should end first epoch properly with one deposit', async () => {
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.distirbute();

            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await payout.transfer(staking.address, TWO_THOUSAND);

            await staking.distirbute();

            let epoch1 = await staking.epoch('1');

            console.log(epoch1);

            console.log(await staking.userStakeMultiplierAtEpoch(user.address, '1'));
            console.log(await staking.userStakeMultiplier(user.address));

            await staking.connect(user).claim(user.address, ['1'])

            let epoch1After = await staking.epoch('1');

            console.log(epoch1After);
        });
    });

    describe('stake()', () => {
        it('should stake', async () => {
            console.log(await staking.meanMultiplier());
            console.log(await staking.multiplierIndex());
            await staking.stake(deployer.address, ONE_THOUSAND);
            console.log(await staking.meanMultiplier());
            console.log(await staking.multiplierIndex());

            await network.provider.send("evm_increaseTime", [5184010]);
            await network.provider.send("evm_mine");

            console.log(await staking.meanMultiplier());
            console.log(await staking.multiplierIndex());

            await staking.stake(deployer.address, ONE_THOUSAND);

            console.log(await staking.meanMultiplier());
            console.log(await staking.multiplierIndex());

            await staking.unstake(deployer.address, ONE_THOUSAND);

            console.log(await staking.meanMultiplier());
            console.log(await staking.multiplierIndex())
        });
    });

    describe('unstake()', () => {
        it('should unstake', async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            let stakeDetailsBefore = await staking.stakeDetails(deployer.address);

            expect(stakeDetailsBefore[0]).to.equal(ONE_THOUSAND);

            await staking.unstake(deployer.address, ONE_THOUSAND);

            let stakeDetailsAfter = await staking.stakeDetails(deployer.address);

            expect(stakeDetailsAfter[0]).to.equal('0');
        });
    });

    describe('claim()', () => {
        it('should claim', async () => {
            await payout.transfer(staking.address, FIVE_THOUSAND);

            await staking.stake(user.address, ONE_THOUSAND);
        });
    });


});