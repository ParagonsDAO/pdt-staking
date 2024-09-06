# pdt-staking

## Overview
The PDT staking contract is the second version of a smart contract designed to distribute ERC20 tokens to stakers over defined epochs. This contract has been forked(PDTStaking.sol) from the original version and enhanced with new features and deployed on the Base blockchain at https://basescan.org/address/0x51e025cb3ee0b99a84f7fb80994198281e29aa3e.


### Key Features of StakedPDT.sol:
- Distributes arbitrary ERC20 tokens to stakers
- Stakers are based on weight in the contract which is based on the amount and the size of total staked and the time of the initial stake 
- Time-weighted staking rewards within each epoch
- Stakers receive stPDT receipt tokens equal to their staked amount

## Contract Audits
You can find the audits for this contract here: 

Zellic - https://github.com/Zellic/publications/blob/master/PDT%20Staking%20V2%20-%20Zellic%20Audit%20Report.pdf
Hashlock - https://hashlock.com/audits/paragonsdao

## Bug Bounty

ParagonsDAO hosts bug bounties at these addresses 
- Hashlock - https://hashlock.com/bug-bounty/paragonsdao
- ImmuneFi - https://immunefi.com/bounty/paragonsdao/ 

If you've found a vulnerability on this contract, it must be submitted through one of these platforms. See the bounty pages for more details on accepted vulnerabilities, payout amounts, and rules of participation.

## Contract Structure
### Constructor
/**
 * @notice Constructs the contract.
 * @param name The name of receipt token
 * @param symbol The symbol of receipt token
 * @param initialEpochLength The duration of each epoch in seconds
 * @param firstEpochStartIn The duration of seconds the first epoch will starts in
 * @param pdtAddress The address of PDT token
 * @param initialOwner The address of initial owner
 */

### Owner Functions
1. updateEpochLength
2. updateRewardsExpiryThreshold
3. registerNewRewardToken
4. distribute
5. withdrawRewardTokens
6. updateWhitelistedContract

### External Functions
1. stake
2. unstake
3. claim

### View Functions
1. pendingRewards
2. claimAmountForEpoch
3. userWeightAtEpoch
4. userTotalWeight
5. contractWeightAtEpoch
6. contractWeight

### Internal Functions
1. _weightIncreaseSinceInteraction
2. _adjustContractWeight
3. _setUserWeightAtEpoch

## Staking Mechanism
- Stakers receive stPDT receipt tokens equal to their staked amount.
- Staking is time-weighted within each epoch.
- Earlier stakers in an epoch receive more rewards than later stakers in an epoch.
- Rewards can be claimed at the end of each epoch
  
## Epoch System
- Each epoch has a defined duration set by the contract.
- The contract is funded with reward tokens before the start of each epoch.
- Multiple different ERC20 tokens can be distributed as rewards in a single epoch.

## Reward Distribution
- Rewards are calculated based on the staker's amount against the pool of stakers and duration of stake within the epoch.
- The contract supports flexible reward token registration, allowing for various ERC20 tokens to be distributed.


## Tests
In the repo you can a whole host of foundry test than are explained here:

`StakedPDT_base.sol` This file contains  test for the base contract or interface for the StakedPDT system, defining core structures and functions.

`StakedPDT_claim.t.sol` Tests the claiming functionality, ensuring users can correctly claim their rewards after staking periods.

`StakedPDT_constructor.t.sol` Verifies that the contract is correctly initialised with the proper parameters during deployment.

`StakedPDT_distribute.t.sol` Tests the distribution mechanism of rewards, ensuring they are correctly allocated to stakers based on their stake and time(starting and epoch).

`StakedPDT_registerNewRewardToken.t.sol` Tests the functionality of adding new reward tokens to the system, ensuring they can be correctly registered and distributed.

`StakedPDT_stake.t.sol` Focuses on testing the staking mechanism, including correct token transfers and receipt token minting.

`StakedPDT_stake_unstake_claim.t.sol` Comprehensive tests covering the full cycle of staking, unstaking, and claiming rewards, ensuring these core functions work together correctly.

`StakedPDT_updateEpochLength.t.sol` Tests the ability to update the epoch length, ensuring it affects reward calculations and distributions correctly.


This documentation provides a high-level overview of the PDT staking contract, its key features, and its core functionalities. For detailed information on each function, refer to the inline comments in the contract code.

