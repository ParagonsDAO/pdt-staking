PDTStaking v2 

# Overview
The PDT staking contract is the second version of a smart contract designed to distribute ERC20 tokens to stakers over defined epochs. This contract has been forked (`PDTStaking.sol`) from the original version and enhanced with new features and deployed on a L2.

## Key Features of `StakedPDT.sol`:
- Distributes arbitrary ERC20 tokens to stakers
- Stakers are based on weight in the contract which is based on the amount and the size of total staked and the time of the initial stake 
- Time-weighted staking rewards within each epoch
- Stakers receive stPDT receipt tokens equal to their staked amount

## Contract Structure
### Constructor
 * @param name The name of receipt token
 * @param symbol The symbol of receipt token
 * @param initialEpochLength The duration of each epoch in seconds
 * @param firstEpochStartIn The duration of seconds the first epoch will starts in
 * @param pdtAddress The address of PDT token
 * @param initialOwner The address of initial owner

### Owner Functions
- `updateEpochLength`
- `updateRewardsExpiryThreshold`
- `registerNewRewardToken`
- `distribute`
- `withdrawRewardTokens`
- `updateWhitelistedContract`

### External Functions
- `stake`
- `unstake`
- `claim`

### View Functions
- `pendingRewards`
- `claimAmountForEpoch`
- `userWeightAtEpoch`
- `userTotalWeight`
- `contractWeightAtEpoch`
- `contractWeight`

### Internal Functions
- `_weightIncreaseSinceInteraction`
- `_adjustContractWeight`
- `_setUserWeightAtEpoch`

## Staking Mechanism
Stakers receive stPDT receipt tokens equal to their staked amount.
Staking is time-weighted within each epoch.
Earlier stakers in an epoch receive more rewards than later stakers in an epoch.
Rewards can be claimed at the end of each epoch.

## Epoch System
Each epoch has a defined duration set by the contract.
The contract is funded with reward tokens before the start of each epoch.
Multiple different ERC20 tokens can be distributed as rewards in a single epoch.

## Reward Distribution
Rewards are calculated based on the staker's amount against the pool of stakers and duration of stake within the epoch.
The contract supports flexible reward token registration, allowing for various ERC20 tokens to be distributed.

## Tests
In the repo you can find a whole host of foundry tests that are explained here:

- `StakedPDT_base.sol`: This file contains tests for the base contract or interface for the StakedPDT system, defining core structures and functions.
- `StakedPDT_claim.t.sol`: Tests the claiming functionality, ensuring users can correctly claim their rewards after staking periods.
- `StakedPDT_constructor.t.sol`: Verifies that the contract is correctly initialized with the proper parameters during deployment.
- `StakedPDT_distribute.t.sol`: Tests the distribution mechanism of rewards, ensuring they are correctly allocated to stakers based on their stake and time (starting and epoch).
- `StakedPDT_registerNewRewardToken.t.sol`: Tests the functionality of adding new reward tokens to the system, ensuring they can be correctly registered and distributed.
- `StakedPDT_stake.t.sol`: Focuses on testing the staking mechanism, including correct token transfers and receipt token minting.
- `StakedPDT_stake_unstake_claim.t.sol`: Comprehensive tests covering the full cycle of staking, unstaking, and claiming rewards, ensuring these core functions work together correctly.
- `StakedPDT_updateEpochLength.t.sol`: Tests the ability to update the epoch length, ensuring it affects reward calculations and distributions correctly.

This documentation provides a high-level overview of the PDT staking contract, its key features, and its core functionalities. For detailed information on each function, refer to the inline comments in the contract code.

## Development

### Setup

```bash
forge install --shallow forge-std
forge install --shallow OpenZeppelin/openzeppelin-contracts
yarn install
```

### Build

```bash
forge build
```

## Deploy

```bash
forge create --rpc-url "<your_rpc_url>" \
  --constructor-args <initial_epoch_length> <first_epoch_start_in> "<PDTOFT_address>" "<initial_owner_address>" \
  --private-key "<your_private_key>" \
  --etherscan-api-key "<your_basescan_api_key>" \
  --verify \
  src/contracts/PDTStakingV2.sol:PDTStakingV2
```

## Hashlock Bug Bounty

ParagonsDAO hosts a bug bounty on Hashlock at this address https://hashlock.com/bug-bounty/paragonsdao. 

If you've found a vulnerability on this contract, it must be submitted through Hashlock. See the bounty page for more details on accepted vulnerabilities, payout amounts, and rules of participation.
