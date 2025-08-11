# Privacy Pool Paymasters - Individual Deployment Scripts

This directory contains individual deployment scripts for each contract component.

## Available Deployment Scripts

### Core Verifiers
- `DeployWithdrawalVerifier.s.sol` - ZK verifier for withdrawal proofs
- `DeployCommitmentVerifier.s.sol` - ZK verifier for commitment proofs

### Core Infrastructure  
- `DeployEntrypoint.s.sol` - Privacy Pool main entrypoint (with UUPS proxy)
- `DeployPrivacyPool.s.sol` - ETH Privacy Pool implementation

### Account Abstraction
- `DeployPaymaster.s.sol` - Main Privacy Pool Paymaster contract
- `DeployAccountValidator.s.sol` - Validator for SimpleAccount factory

### Testing
- `DeployCounter.s.sol` - Simple counter contract for testing

## Deployment Order

For a complete system deployment, follow this order:

1. **Deploy Verifiers** (independent)
   ```bash
   npm run deploy:withdrawal-verifier:local
   npm run deploy:commitment-verifier:local
   ```

2. **Deploy Entrypoint** (independent)
   ```bash
   npm run deploy:entrypoint:local
   ```

3. **Deploy Privacy Pool** (requires verifiers + entrypoint)
   ```bash
   # Set environment variables first
   export ENTRYPOINT_ADDRESS=<entrypoint_address>
   export WITHDRAWAL_VERIFIER_ADDRESS=<verifier_address>
   export COMMITMENT_VERIFIER_ADDRESS=<verifier_address>
   
   npm run deploy:privacy-pool:local
   ```

4. **Deploy Paymaster** (requires entrypoint + privacy pool)
   ```bash
   # Set environment variables
   export PRIVACY_ENTRYPOINT_ADDRESS=<entrypoint_address>
   export ETH_PRIVACY_POOL_ADDRESS=<pool_address>
   
   npm run deploy:paymaster:local
   ```

5. **Deploy Account Validator** (requires entrypoint)
   ```bash
   # Set environment variables
   export PRIVACY_ENTRYPOINT_ADDRESS=<entrypoint_address>
   # Optional: export SIMPLE_ACCOUNT_FACTORY_ADDRESS=<factory_address>
   
   npm run deploy:account-validator:local
   ```

## Environment Variables

Create a `.env` file with the following variables:

```bash
# Required for all deployments
PRIVATE_KEY=0x...

# Required for live network deployments
RPC_URL=https://...

# Required for Privacy Pool deployment
ENTRYPOINT_ADDRESS=0x...
WITHDRAWAL_VERIFIER_ADDRESS=0x...
COMMITMENT_VERIFIER_ADDRESS=0x...

# Required for Paymaster deployment
PRIVACY_ENTRYPOINT_ADDRESS=0x...
ETH_PRIVACY_POOL_ADDRESS=0x...

# Required for Account Validator deployment
PRIVACY_ENTRYPOINT_ADDRESS=0x...
# Optional (has default)
SIMPLE_ACCOUNT_FACTORY_ADDRESS=0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985
```

## Usage Examples

### Local Development
```bash
# Start local Anvil node
anvil --host 0.0.0.0 --port 8545

# Deploy individual contracts
npm run deploy:counter:local
npm run deploy:withdrawal-verifier:local
npm run deploy:entrypoint:local
```

### Live Network
```bash
# Set environment variables
export RPC_URL=https://sepolia.infura.io/v3/your-key
export PRIVATE_KEY=0x...

# Deploy with verification
npm run deploy:counter
npm run deploy:withdrawal-verifier
```

## Script Features

Each deployment script:
- ✅ Simple and focused on one contract
- ✅ Returns contract address for scripting
- ✅ Minimal, essential logging only
- ✅ Environment variable configuration
- ✅ Consistent interface across all scripts
