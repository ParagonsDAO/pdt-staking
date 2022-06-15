
const { ethers } = require("hardhat");
const { expect } = require("chai");


describe('Brand Token', () => {

    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const TEN_MILLION = "10000000000000000000000000";
    const HUNDRED_MILLION = "100000000000000000000000000";
    const ONE_THOUSAND = "1000000000000000000000";
    const TWO_THOUSAND = "2000000000000000000000";
    const FIVE_THOUSAND = "5000000000000000000000";

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
        staking = await Staking.deploy('2592000', '86400', pdt.address, payout.address);

        await pdt.mint(deployer.address, TEN_MILLION);
        await pdt.mint(user.address, TEN_MILLION);

        await payout.mint(deployer.address, TEN_MILLION);
        await payout.mint(user.address, TEN_MILLION);

        await pdt.approve(staking.address, TEN_MILLION);
        await pdt.connect(user).approve(staking.address, TEN_MILLION);
    });

    describe('constructor()', () => {
        it('should set epoch length correctly', async () => {
            expect(await staking.epochLength()).to.equal('86400');
        });

        it('should set time to double correctly', async () => {
            expect(await staking.timeToDouble()).to.equal('2592000');
        });

        it('should set pdt token correctly', async () => {
            expect(await staking.pdt()).to.equal(pdt.address);
        });

        it('should set payout token correctly', async () => {
            expect(await staking.rewardToken()).to.equal(payout.address);
        });
    });

});