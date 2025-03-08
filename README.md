# Kryzel Staking Contracts

Smart contracts for Kryzel token and staking system on Aptos blockchain.

## Contracts

### Kryzel Token (KRZ)
- Custom token implementation on Aptos
- Standard fungible token features
- 1,000,000,000 Supply
- Contract: `kryzel_coin_v7.move`

### Staking System
- Flexible staking mechanism with restaking capability
- 2-day staking periods
- Active/Pending/Expired status management
- Contract: `kryzel_staking_v7.move`

## Features
- Token staking with configurable periods
- Restaking mechanism
- Status tracking for stakes
- Automated status updates
- Event emission for tracking

## Testing
Test suite available in `krz_staking_2min_tests.move`

## Deployment
Currently deployed on Aptos testnet at:
name = "Kryzel_v7"
version = "1.0.0"

[addresses]
test_addr = "0x69d738995c2d7ee9b59c87a6b4ba578ebb6848c9d8de4f47f9ea9512584f4de3"
