# Privacy Pool Paymaster

A secure ERC-4337 paymaster implementation that sponsors gas fees for Privacy Pool withdrawal operations while ensuring only valid transactions are executed. This enables **decentralized Privacy Pool withdrawals without relying on centralized relayer services**.

## Overview

The `SimplePrivacyPoolPaymaster` sponsors user operations for Privacy Pool withdrawals. It validates the entire withdrawal flow before sponsoring, guaranteeing transaction success and preventing gas waste.

## How It Works

### Architecture
The paymaster integrates with three core contracts:
- **Privacy Pool Entrypoint**: Main relay contract that processes withdrawals
- **ETH Privacy Pool**: The privacy pool where funds are deposited and stored  
- **Withdrawal Verifier**: Groth16 verifier for zero-knowledge proofs

### Deterministic Smart Account Pattern
The paymaster uses a **deterministic smart account approach** for enhanced security and user experience:
- **Single Expected Account**: Only accepts UserOperations from a pre-configured smart account address
- **Pre-deployment Required**: Smart account must be deployed before withdrawal operations (prevents deployment cost charging)
- **Recipient-based Refunds**: Refunds go directly to the recipient specified in RelayData, not the smart account
- **Cost Predictability**: Users only pay for withdrawal transactions, not account deployment

### Validation Process
The paymaster performs a 7-step validation process:
1. **Configuration Check** - Ensures expected smart account is configured
2. **Sender Validation** - Verifies UserOperation comes from expected smart account  
3. **Deployment Check** - Ensures smart account is already deployed (no initCode)
4. **Gas Limit Check** - Validates sufficient post-operation gas limit
5. **CallData Validation** - Direct extraction of SimpleAccount.execute() parameters
6. **ZK Proof Verification** - Verifies zero-knowledge proofs and Privacy Pool state consistency
7. **Economic Check** - Ensures relay fees cover gas costs and paymaster receives payment

### Smart Account Configuration  
The paymaster owner can configure the expected smart account:

```solidity
function setExpectedSmartAccount(address account) external onlyOwner
```

### Gas Management & Cost Protection
The paymaster charges approximately the gas cost of UserOperation execution and refunds any excess funds received (as part of relay fees) back to the **recipient address**. It **only sponsors operations for pre-deployed accounts** to protect users from unexpected deployment costs.

## Development

### Prerequisites

- Node.js (v18+)
- Foundry
- TypeScript
- Docker (for E2E testing)

### Installation

```shell
# Clone with submodules or initialize them if already cloned
git submodule update --init --recursive

# Install dependencies
npm install
```

### Build

```shell
npm run build
# or
forge build
```

### Testing

```shell
npm test
# or
forge test
```

### Deployment

Deploy to a local fork of Base mainnet:

```shell
npm run deploy
```

This command will:
1. Start an Anvil fork of Base mainnet
2. Deploy the paymaster contracts using Forge
3. Clean up the local node

### End-to-End Testing

Run the complete E2E test flow with mock AA environment:

```shell
cd mock-aa-environment
docker compose up -d
cd ..
npm run e2e
```

### Configuration

Copy environment template:
```shell
cp .env.example .env
```

### Integration Example

```typescript
import { createSmartAccountClient } from "permissionless";
import { privateKeyToAccount } from "viem/accounts";

// Configure paymaster in your smart account client
const smartAccountClient = createSmartAccountClient({
  // ... other config
  paymaster: {
    async getPaymasterStubData() {
      return {
        paymaster: PAYMASTER_ADDRESS,
        paymasterData: "0x",
        paymasterPostOpGasLimit: 32000n,
      };
    },
    async getPaymasterData() {
      return {
        paymaster: PAYMASTER_ADDRESS,
        paymasterData: "0x", // Paymaster validates via callData
        paymasterPostOpGasLimit: 32000n,
      };
    }
  }
});
```
