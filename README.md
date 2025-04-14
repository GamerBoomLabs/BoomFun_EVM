# BoomFun Protocol

BoomFun Protocol is a decentralized platform for creating, trading, and managing tokenized assets on the Ethereum blockchain. The protocol leverages bonding curves to provide a fair and transparent pricing mechanism for digital assets.

## Overview

BoomFun Protocol enables creators to launch their own tokens with an automated market maker and built-in liquidity. The protocol features:

- Bonding curve-based token pricing
- Automatic transition to DEX liquidity pools when reaching market cap thresholds
- Seamless integration with Uniswap V2
- Platform fees for sustainability
- Transparent and predictable token economics

## Smart Contracts

The project includes three main smart contracts:

1. **BoomFunProtocol.sol**: The core protocol contract that manages token creation, pricing via bonding curves, and DEX transitions.
2. **BoomFunToken.sol**: The token contract used by the protocol to create tokens for creators.
3. **BoomToken.sol**: A utility token for testing the protocol.

## Getting Started

### Prerequisites

- Node.js (v14+)
- npm or yarn
- Hardhat

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd boomfun-protocol

# Install dependencies
npm install
```

### Testing

Run the test suite with:

```bash
npx hardhat test
```

### Deployment

Deploy to a local Hardhat network:

```bash
npx hardhat node
npx hardhat run scripts/deploy.js --network localhost
```

Deploy to a testnet or mainnet (configure your `.env` file first):

```bash
npx hardhat run scripts/deploy.js --network <network-name>
```

## Technical Details

### Bonding Curve

The protocol uses a custom bonding curve formula to determine token prices:

- Token price increases as more tokens are purchased
- Price is calculated using the formula: `y = A - (B / (30 + x/3000))`
- Parameters A and B are configured to provide reasonable price appreciation

### DEX Phase

When a token reaches a predefined market cap threshold (263,300 tokens), it transitions to the DEX phase:
- Remaining tokens and collected funds are used to create permanent liquidity on Uniswap V2
- After the transition, tokens can only be traded through the DEX

## License

This project is licensed under the ISC License.