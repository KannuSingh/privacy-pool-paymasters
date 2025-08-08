# Privacy Pool Paymaster

A secure ERC-4337 paymaster implementation that sponsors gas fees for Privacy Pool withdrawal operations while ensuring only valid transactions are executed. This enables **decentralized Privacy Pool withdrawals without relying on centralized relayer services**.

## Overview

The `SimplePrivacyPoolPaymaster` sponsors user operations for Privacy Pool withdrawals. It validates the entire withdrawal flow before sponsoring, guaranteeing transaction success and preventing gas waste.

## How It Works

### Architecture
The paymaster integrates with four core contracts:
- **Privacy Pool Entrypoint**: Main relay contract that processes withdrawals
- **ETH Privacy Pool**: The privacy pool where funds are deposited and stored
- **Withdrawal Verifier**: Groth16 verifier for zero-knowledge proofs
- **Account Validators**: Modular validators for different account types

### Validation Process
The paymaster performs a 4-step validation process:
1. **Account Factory Validation** - Checks if the account factory is supported
2. **Transaction Structure** - Validates the UserOperation calls the correct Privacy Pool functions
3. **ZK Proof Verification** - Verifies zero-knowledge proofs and Privacy Pool state consistency  
4. **Economic Check** - Ensures relay fees cover gas costs and paymaster receives payment

### Account Factory Management
The paymaster maintains a **whitelist of supported account factories** to ensure security and compatibility. Each factory has a dedicated validator that understands its specific callData format. This approach:
- **Prevents malicious factories** from creating invalid transactions
- **Enables multi-account support** (SimpleAccount, Biconomy, etc.)
- **Ensures proper callData decoding** for each account type
- **Maintains security standards** through vetted validators

```solidity
function addSupportedFactory(address factory, IAccountValidator validator) external onlyOwner
function removeSupportedFactory(address factory) external onlyOwner
function getSupportedFactories() external view returns (address[] memory)
```

### Gas Management & Fresh Accounts
The paymaster charges approximately the gas cost of UserOperation execution and refunds any excess funds received (as part of relay fees) back to the user's account. It **only sponsors operations for fresh accounts** (those with `initCode`) to ensure security based on supported factories and is suitable for privacy use cases.

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
