const { ethers } = require("hardhat");
const { expect } = require("chai");
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");

describe("PDT Staking", () => {
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const TEN_MILLION = "10000000000000000000000000";
    const HUNDRED_MILLION = "100000000000000000000000000";
    const ONE_HUNDRED = "100000000000000000000";
    const FIVE_HUNDRED = "500000000000000000000";
    const ONE_THOUSAND = "1000000000000000000000";
    const TWO_THOUSAND = "2000000000000000000000";
    const THREE_THOUSAND = "3000000000000000000000";
    const FIVE_THOUSAND = "5000000000000000000000";
    const HUNDRED_THOUSAND = "100000000000000000000000";
    const FIFTY_THOUSAND = "50000000000000000000000";
    const ONE_MILLION = "1000000000000000000000000";
    const ONE_DAY = "86400";
    const TWO_DAYS = "172800";
    const FIFTEEN_DAYS = "1296000";
    const THIRTY_DAYS = "2592000";
    const ONE_GWEI = 1000000000;

    let // Used as default deployer for contracts, asks as owner of contracts.
        deployer,
        user,
        user2,
        ERC20Factory,
        pdt,
        payout,
        Staking,
        staking,
        deployTimestmap;

    beforeEach(async () => {
        [deployer, user, user2] = await ethers.getSigners();

        ERC20Factory = await ethers.getContractFactory("MockERC20");

        pdt = await ERC20Factory.deploy();
        payout = await ERC20Factory.deploy();

        Staking = await ethers.getContractFactory("PDTStaking");
        staking = await Staking.deploy(
            THIRTY_DAYS,
            ONE_DAY,
            ONE_DAY,
            pdt.address,
            payout.address,
            deployer.address
        );

        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        deployTimestmap = block.timestamp;

        await pdt.mint(deployer.address, TEN_MILLION);
        await pdt.mint(user.address, TEN_MILLION);

        await payout.mint(deployer.address, TEN_MILLION);

        await pdt.approve(staking.address, TEN_MILLION);
        await pdt.connect(user).approve(staking.address, TEN_MILLION);
    });

    describe("constructor()", () => {
        it("should set time to double correctly", async () => {
            expect(await staking.timeToDouble()).to.equal(THIRTY_DAYS);
        });

        it("should set epoch length correctly", async () => {
            expect(await staking.epochLength()).to.equal(ONE_DAY);
        });

        it("should set start time correctly", async () => {
            let currentEpoch = await staking.currentEpoch();
            expect(currentEpoch[3]).to.equal(+deployTimestmap + +ONE_DAY);
        });

        it("should set pdt token correctly", async () => {
            expect(await staking.pdt()).to.equal(pdt.address);
        });

        it("should set payout token correctly", async () => {
            expect(await staking.prime()).to.equal(payout.address);
        });

        it("should set owner properly", async () => {
            expect(await staking.owner()).to.equal(deployer.address);
        });
    });

    describe("updateEpochLength", () => {
        it('should NOT let non owner address to update epoch length', async () => {
            await expect(staking.connect(user).updateEpochLength(THIRTY_DAYS)).to.be.revertedWith("NotOwner()");
            expect(await staking.epochLength()).to.equal(ONE_DAY);
        });

        it('should allow owner to update epoch length', async () => {
            await staking.connect(deployer).updateEpochLength(THIRTY_DAYS)
            expect(await staking.epochLength()).to.equal(THIRTY_DAYS);
        });
    });

    describe("transferOwnership()", () => {
        it('should NOT let non owner address transfer ownership', async () => {
            await expect(staking.connect(user).transferOwnership(user.address)).to.be.revertedWith("NotOwner()");
            expect(await staking.owner()).to.equal(deployer.address);
        });

        it('should NOT allow ownership to be transferre to zero address', async () => {
            await expect(staking.connect(deployer).transferOwnership(ZERO_ADDRESS)).to.be.revertedWith("ZeroAddress()");
            expect(await staking.owner()).to.equal(deployer.address);
        });

        it('should allow owner to transfer ownership', async () => {
            await staking.connect(deployer).transferOwnership(user.address)
            expect(await staking.owner()).to.equal(user.address);
        });
    });

    describe("distribute()", () => {
        it("should NOT start first epoch after deployment, if not passed end time", async () => {
            expect(await staking.epochId()).to.equal("0");
            await payout.transfer(staking.address, ONE_HUNDRED);

            await staking.distribute();
            let currentEpoch = await staking.currentEpoch();

            expect(currentEpoch[0]).to.equal("0");
            expect(await staking.epochId()).to.equal("0");
        });

        it("should start first epoch after deployment, if passed end time", async () => {
            expect(await staking.epochId()).to.equal("0");
            await payout.transfer(staking.address, ONE_HUNDRED);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            let currentEpoch = await staking.currentEpoch();

            expect(currentEpoch[0]).to.equal(ONE_HUNDRED);
            expect(await staking.epochId()).to.equal("1");
        });
    });

    describe("stake()", () => {
        it("should NOT stake if trying to stake more than balance", async () => {
            await expect(
                staking.connect(user2).stake(user2.address, TWO_THOUSAND)
            ).to.be.revertedWith("MoreThanBalance()");
        });

        it("should stake and properly set stake detials", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            const stakeTimestamp = block.timestamp;

            const stake = await staking.stakeDetails(deployer.address);
            expect(stake[0]).to.equal(ONE_THOUSAND);
            expect(stake[1]).to.equal(stakeTimestamp);
            expect(stake[2]).to.equal(ONE_THOUSAND);
        });

        it("should stake again and update properly", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            await staking.stake(deployer.address, TWO_THOUSAND);

            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            const secondStakeTimestamp = block.timestamp;
            const stakeAfter = await staking.stakeDetails(deployer.address);

            expect(stakeAfter[0]).to.equal(THREE_THOUSAND);
            expect(stakeAfter[1]).to.equal(secondStakeTimestamp);
        });

        it("should have user weight = contract weight when only staker", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            expect(await staking.contractWeight()).to.equal(
                await staking.userTotalWeight(deployer.address)
            );

            await staking.stake(deployer.address, TWO_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            expect(await staking.contractWeight()).to.equal(
                await staking.userTotalWeight(deployer.address)
            );
        });

        it("should have sum of stakers weight = total weight of contact", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            await staking.stake(user.address, TWO_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [2592000]);
            await network.provider.send("evm_mine");

            await staking.stake(user2.address, FIVE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            const sumOfUserWeight =
                +(await staking.userTotalWeight(deployer.address)).toString() +
                +(await staking.userTotalWeight(user.address)).toString() +
                +(await staking.userTotalWeight(user2.address)).toString();

            expect(+(await staking.contractWeight()).toString()).to.equal(+sumOfUserWeight);
        });
    });

    describe("unstake()", () => {
        it("should unstake and update user properly", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            let blockNum = await ethers.provider.getBlockNumber();
            let block = await ethers.provider.getBlock(blockNum);
            const stakeTimestamp = block.timestamp;

            let stakeDetailsBefore = await staking.stakeDetails(deployer.address);

            expect(stakeDetailsBefore[0]).to.equal(ONE_THOUSAND);
            expect(stakeDetailsBefore[1]).to.equal(stakeTimestamp);
            expect(stakeDetailsBefore[2]).to.equal(ONE_THOUSAND);

            await staking.unstake(deployer.address);

            blockNum = await ethers.provider.getBlockNumber();
            block = await ethers.provider.getBlock(blockNum);
            const unstakeTimestamp = block.timestamp;

            let stakeDetailsAfter = await staking.stakeDetails(deployer.address);

            expect(stakeDetailsAfter[0]).to.equal("0");
            expect(stakeDetailsAfter[1]).to.equal(unstakeTimestamp);
            expect(stakeDetailsAfter[2]).to.equal("0");
        });

        it("should NOT unstake if already unstaked", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);

            await staking.unstake(deployer.address);
            await expect(staking.unstake(deployer.address)).to.be.revertedWith("NothingStaked()");
        });

        it("should unstake and update contract properly, when only one staker", async () => {
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            await staking.stake(deployer.address, TWO_THOUSAND);

            await staking.unstake(deployer.address);

            expect(await staking.contractWeight()).to.equal("0");
            expect(await staking.userTotalWeight(deployer.address)).to.equal("0");
        });

    });

    describe("claim()", () => {
        it('should NOT allow claim for invalid epoch', async () => {
            /// EPOCH 0 ///
            await expect(staking.connect(user).claim(user.address, ['1'])).to.be.revertedWith("InvalidEpoch()");
        });

        it('should NOT allow claim for epoch already claimed', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            /// EPOCH 2 ///
            await staking.distribute();

            await staking.connect(user).claim(user.address, ['1'])
            await expect(staking.connect(user).claim(user.address, ['1'])).to.be.revertedWith("EpochClaimed()");
        });

        it('should claim properly when just one staker', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 2 ///
            let epoch1Before = await staking.epoch('1');
            let rewardBalanceBefore = await payout.balanceOf(user.address);

            expect(epoch1Before[1]).to.equal("0");

            await staking.connect(user).claim(user.address, ['1'])

            let rewardBalanceAfter = await payout.balanceOf(user.address);

            let epoch1After = await staking.epoch('1');

            expect(epoch1After[1]).to.equal(FIVE_THOUSAND);
            expect(+rewardBalanceAfter).to.equal(+rewardBalanceBefore + +FIVE_THOUSAND);
        });

        it('should claim proeperly with multiple addresses claiming with NO unstaking', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await payout.transfer(staking.address, TWO_THOUSAND);

            await staking.stake(deployer.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            await network.provider.send("evm_increaseTime", [89410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 3 ///

            let epoch1Before = await staking.epoch('1');
            let epoch2Before = await staking.epoch('2');

            expect(epoch1Before[1]).to.equal('0');
            expect(epoch2Before[1]).to.equal('0');

            await staking.connect(user).claim(user.address, ['1'])
            await staking.connect(deployer).claim(deployer.address, ['1']);

            await staking.connect(user).claim(user.address, ['2'])
            await staking.connect(deployer).claim(deployer.address, ['2'])

            let epoch1After = await staking.epoch('1');
            let epoch2After = await staking.epoch('2');

            expect(epoch1After[1]).to.equal(FIVE_THOUSAND);
            expect(epoch2After[1]).to.equal(TWO_THOUSAND);
        });

        it('should claim proeperly with multiple addresses claiming with unstaking', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);
            await staking.stake(user2.address, FIVE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await payout.transfer(staking.address, TWO_THOUSAND);

            await staking.stake(deployer.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            await staking.connect(user).unstake(user.address);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [129410]);
            await network.provider.send("evm_mine");
            

            await staking.distribute();

            /// EPOCH 3 ///

            expect(await staking.claimAmountForEpoch(deployer.address, '1')).to.equal('0');

            let rewardBalanceBeforeDeployer = await payout.balanceOf(deployer.address);

            await staking.connect(user).claim(user.address, ['1'])
            await staking.connect(user2).claim(user2.address, ['1'])
            await staking.connect(deployer).claim(deployer.address, ['1']);
            let rewardBalanceAfterDeployer = await payout.balanceOf(deployer.address);

            expect(rewardBalanceAfterDeployer).to.equal(rewardBalanceBeforeDeployer);

            expect(await staking.claimAmountForEpoch(user.address, '2')).to.equal('0');

            let rewardBalanceBeforeUser = await payout.balanceOf(user.address);

            await staking.connect(user).claim(user.address, ['2'])
            await staking.connect(user2).claim(user2.address, ['2'])
            await staking.connect(deployer).claim(deployer.address, ['2'])

            let rewardBalanceAfterUser = await payout.balanceOf(user.address);
            expect(rewardBalanceAfterUser).to.equal(rewardBalanceBeforeUser);

            let epoch1After = await staking.epoch('1');
            let epoch2After = await staking.epoch('2');


            expect(epoch1After[1]).to.equal(FIVE_THOUSAND);
            expect(epoch2After[1]).to.equal(TWO_THOUSAND);
        });


    });

    describe("userTotalWeight()", () => {
        it('should have total weight as 0 if nothing is staked', async () => {
            expect(await staking.userTotalWeight(user.address)).to.equal('0');
        });

        it('should have total weight at 0 if user unstakes', async () => {
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.connect(user).unstake(user.address);
            expect(await staking.userTotalWeight(user.address)).to.equal('0');
        })

        it('should have total weight initally be amount staked', async () => {
            await staking.stake(user.address, ONE_THOUSAND);
            expect(await staking.userTotalWeight(user.address)).to.equal(ONE_THOUSAND);
        });

        it('should account for pending weight increase since last interaction', async () => {
            await staking.stake(user.address, ONE_THOUSAND);

            /// 2592000 = 30 days, Double period
            await network.provider.send("evm_increaseTime", [2592000]);
            await network.provider.send("evm_mine");
            expect(await staking.userTotalWeight(user.address)).to.equal(TWO_THOUSAND);
        });
    });

    describe("contractWeightAtEpoch()", () => {
        it('should fail if trying to get weight for current epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.contractWeightAtEpoch('1')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should fail if trying to get contract weight for future epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.connect(user).contractWeightAtEpoch('2')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should return proper contract weight at end of epoch', async () => {
            /// EPOCH 0 ///
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            await staking.stake(user.address, TWO_THOUSAND);

            /// EPOCH 1 ///
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [2592000]);
            await network.provider.send("evm_mine");

            await staking.stake(user2.address, FIVE_THOUSAND);

            /// EPOCH 2 ///

            await staking.connect(user).unstake(user.address);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            const sumOfUserWeight1 =
                +(await staking.userWeightAtEpoch(deployer.address, '1')).toString() +
                +(await staking.userWeightAtEpoch(user.address, '1')).toString() +
                +(await staking.userWeightAtEpoch(user2.address, '1')).toString();

            expect(+(await staking.contractWeightAtEpoch('1')).toString()).to.equal(+sumOfUserWeight1);

            const sumOfUserWeight2 =
                +(await staking.userWeightAtEpoch(deployer.address, '2')).toString() +
                +(await staking.userWeightAtEpoch(user.address, '2')).toString() +
                +(await staking.userWeightAtEpoch(user2.address, '2')).toString();

            expect(Number(sumOfUserWeight2 - (await staking.contractWeightAtEpoch('2')))).to.be.lessThan(ONE_GWEI);
        });

    });

    describe("claimAmountForEpoch()", () => {
        it('should fail if trying to get claim amount for current epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.claimAmountForEpoch(user.address, '1')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should fail if trying to get claim amount for future epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.connect(user).claimAmountForEpoch(user.address, '2')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should return claim amount when weight not set in contract at epoch yet', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 2 ///
            let epoch1 = await staking.epoch('1');
            expect(await staking.epochLeftOff(user.address)).to.equal('0')
            expect(epoch1[0]).to.equal(await staking.claimAmountForEpoch(user.address, '1'));
        });

        it('should return claim amount when weight is set in contract at epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 2 ///
            let epoch1 = await staking.epoch('1');
            await staking.stake(user.address, '0');
            expect(await staking.epochLeftOff(user.address)).to.equal('2')
            expect(epoch1[0]).to.equal(await staking.claimAmountForEpoch(user.address, '1'));
        });

        it('should return 0 when already claimed', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 2 ///
            await staking.connect(user).claim(user.address, ['1'])
            expect(await staking.claimAmountForEpoch(user.address, '1')).to.equal('0');
        });
    });

    describe("userWeightAtEpoch()", () => {
        it('should fail if trying to get user weight for current epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.userWeightAtEpoch(user.address, '1')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should fail if trying to get user weight for future epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user.address, ONE_THOUSAND);

            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await expect(staking.connect(user).userWeightAtEpoch(user.address, '2')).to.be.revertedWith("InvalidEpoch()");
        });

        it('should return 0 if stake triggers epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");
            await staking.stake(user.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            expect(await staking.userWeightAtEpoch(user.address, '1')).to.equal('0');
        });

        it('should return proper user weight at epoch', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");
            await staking.stake(user.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            expect(await staking.userWeightAtEpoch(user.address, '1')).to.equal('0');

            await network.provider.send("evm_increaseTime", [142800]);
            await network.provider.send("evm_mine");
            await staking.distribute();

            /// EPOCH 3 ///
            const additionalWeight = ONE_THOUSAND * (1/30);
            expect(await staking.userWeightAtEpoch(user.address, '2') - additionalWeight).to.equal(+ONE_THOUSAND);
        });

    });

    describe("contractWeight()", () => {
        it('should be weight of 0 if no one has staked yet', async () => {
            expect(await staking.contractWeight()).to.equal('0');
        });

        it('should be weight of 0 if everyone unstaked', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await staking.stake(user2.address, ONE_THOUSAND);
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");
            await staking.stake(user.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [142800]);
            await network.provider.send("evm_mine");

            await staking.connect(user).unstake(user.address);
            await staking.connect(user2).unstake(user2.address);

            expect(await staking.contractWeight()).to.equal('0');
        });

        it('should have weight properly when one staker', async () => {
            /// EPOCH 0 ///
            await payout.transfer(staking.address, FIVE_THOUSAND);
            await staking.stake(user.address, ONE_THOUSAND);
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [86410]);
            await network.provider.send("evm_mine");

            await staking.distribute();

            /// EPOCH 1 ///
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");
            await staking.stake(user.address, ONE_THOUSAND);

            /// EPOCH 2 ///
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [142800]);
            await network.provider.send("evm_mine");

            expect(await staking.contractWeight()).to.equal(await staking.userTotalWeight(user.address));
        });

        it('should have weight properly with multiple stakers', async () => {
            /// EPOCH 0 ///
            await staking.stake(deployer.address, ONE_THOUSAND);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [1296000]);
            await network.provider.send("evm_mine");

            await staking.stake(user.address, TWO_THOUSAND);

            /// EPOCH 1 ///
            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [2592000]);
            await network.provider.send("evm_mine");

            await staking.stake(user2.address, FIVE_THOUSAND);

            /// EPOCH 2 ///
            await staking.connect(user).unstake(user.address);

            await network.provider.send("evm_mine");
            await network.provider.send("evm_increaseTime", [172800]);
            await network.provider.send("evm_mine");

            await staking.distribute();
            
            /// EPOCH 3 ///
            const sumOfUserWeight =
                +(await staking.userTotalWeight(deployer.address)).toString() +
                +(await staking.userTotalWeight(user.address)).toString() +
                +(await staking.userTotalWeight(user2.address)).toString();

            expect(Number(sumOfUserWeight - (await staking.contractWeight()))).to.be.lessThan(ONE_GWEI);
        });
    });
});
