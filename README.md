# pdt-staking
The Paragons DAO staking smart contract.

Mainnet Address: https://etherscan.io/address/0xe09c8a88982a85c5b76b1756ec6172d4ad2549d6

The contract went through two independent audits from Certik and Peckshield, both of which found no significant issues with the contract.

You can find the audits below : 

CertiK - https://pub-219b30570f3a4406a348a79b73b8c1b5.r2.dev/staking-CertiK.pdf

Pechshield - https://pub-219b30570f3a4406a348a79b73b8c1b5.r2.dev/staking-PeckShield.pdf

## Development

```bash
forge install --shallow forge-std
forge install --shallow OpenZeppelin/openzeppelin-contracts
forge build
```

## Immunefi Bug Bounty

ParagonsDAO hosts a bug bounty on Immunefi at this address https://immunefi.com/bounty/paragonsdao/. 

If you've found a vulnerability on this contract, it must be submitted through Immunefi's platform. See the bounty page for more details on accepted vulnerabilities, payout amounts, and rules of participation.