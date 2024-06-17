# pdt-staking
The Paragons DAO staking smart contract.

Mainnet Address: https://etherscan.io/address/0xe09c8a88982a85c5b76b1756ec6172d4ad2549d6

The contract went through two independent audits from Certik and Peckshield, both of which found no significant issues with the contract.

You can find the audits below : 

CertiK - https://pub-219b30570f3a4406a348a79b73b8c1b5.r2.dev/staking-CertiK.pdf

Pechshield - https://pub-219b30570f3a4406a348a79b73b8c1b5.r2.dev/staking-PeckShield.pdf

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

## Immunefi Bug Bounty

ParagonsDAO hosts a bug bounty on Immunefi at this address https://immunefi.com/bounty/paragonsdao/. 

If you've found a vulnerability on this contract, it must be submitted through Immunefi's platform. See the bounty page for more details on accepted vulnerabilities, payout amounts, and rules of participation.