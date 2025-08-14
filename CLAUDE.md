# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository implements a privacy-preserving ERC-4337 paymaster system that enables anonymous gas payment through zero-knowledge proofs. The core concept combines Account Abstraction (ERC-4337) with Privacy Pools to allow users to pay for gas fees without revealing their identity using ZK proofs generated from membership in privacy pools.

## Development Commands

### Core Build and Test Commands
- `npm run build` - Build Solidity contracts using Forge
- `npm run test` - Run unit tests using Forge
- `forge test --match-contract <ContractName>` - Run specific contract tests
- `forge test --match-test <testName>` - Run specific test function

### End-to-End Testing
- `npm run e2e` - Run complete E2E test flow (requires mock environment)
- `npm run deploy:e2e` - Deploy contracts for E2E testing using Forge script

### Mock Environment Setup
```bash
cd mock-aa-environment
docker compose up -d  # Start Anvil blockchain + Alto bundler + contract deployer
```

### Circuit and ZK Proof Testing
- Circuit artifacts are pre-built in `circuits/build/` and `circuits/keys/`
- ZK proof generation handled in `utils/WithdrawalProofGenerator.ts`
- Uses snarkjs with Groth16 proving system

## Architecture Overview

### Smart Contract Structure

**Core Paymaster Contract:**
- `src/contracts/SimplePrivacyPoolPaymaster.sol` - Main paymaster implementing ERC-4337 BasePaymaster
  - Validates UserOperations for privacy pool withdrawals using deterministic smart account pattern
  - Embeds withdrawal validation logic to prevent failed sponsorships
  - Uses self-validation pattern for comprehensive withdrawal checking
  - Direct SimpleAccount.execute() callData parsing for efficiency
  - Handles recipient-based refunds and cost calculations
  - Enforces pre-deployed account requirement to prevent deployment cost charging

**Supporting Interfaces:**
- `src/contracts/interfaces/IWithdrawalVerifier.sol` - ZK proof verification interface

**Key Design Patterns:**
- **Deterministic Smart Account**: Single expected account address for all UserOperations
- **Recipient-Based Refunds**: Refunds go directly to RelayData.recipient instead of smart account
- **Self-Validation Pattern**: Paymaster pre-validates privacy pool calls using embedded logic
- **Economics Validation**: Ensures withdrawal fees are sufficient to cover gas costs
- **Pre-deployed Account Only**: Only sponsors operations on existing accounts, prevents deployment cost charging

### Development Environment

**Foundry + Hardhat Hybrid:**
- Primary build system: Foundry (forge)
- TypeScript support: Hardhat with Viem integration
- Testing: Foundry for unit tests, TypeScript for E2E flows

**Key Dependencies:**
- `@account-abstraction/contracts@0.7.0` - ERC-4337 implementation
- `@0xbow/privacy-pools-core-sdk@0.1.22` - Privacy pools core functionality
- `permissionless@0.2.0` - Account abstraction client
- `viem@2.23.2` - Ethereum interaction library
- `snarkjs` - Zero-knowledge proof generation

### Circuit Integration

**ZK Circuit Artifacts:**
- `circuits/keys/` - Proving and verification keys for commitment and withdrawal circuits
- `circuits/build/` - Compiled WASM files and witness calculators
- Circuits generate proofs for anonymous withdrawals from privacy pools

**Proof Generation Flow:**
1. User creates commitment and deposits to privacy pool
2. Setup Approved Set of Participants (ASP) tree
3. Generate withdrawal proof using circuit artifacts
4. Submit UserOperation with proof embedded in calldata
5. Paymaster validates proof and sponsors transaction

### Testing Architecture

**Unit Tests (`test/unit/`):**
- `SimplePrivacyPoolPaymaster.t.sol` - Core paymaster functionality with deterministic account pattern
- Mock integration with Privacy Pool contracts

**Integration Tests (`test/integration/`):**
- End-to-end UserOperation flows with real ZK proofs
- Deterministic smart account integration testing  
- Gas cost validation and recipient-based refund mechanisms

**Mock Infrastructure (`test/mocks/`):**
- `MockEntryPoint.sol` - ERC-4337 EntryPoint mock
- `MockPrivacyPoolComponents.sol` - Privacy pool mocks
- `MockSimplePrivacyPoolPaymaster.sol` - Paymaster testing utilities

**E2E Testing:**
- Full integration test in `scripts/PaymasterE2E.ts`
- Uses real ZK proof generation with circuit artifacts
- Tests complete flow: deposit → proof generation → UserOperation → execution

## Key Configuration Files

### Foundry Configuration (`foundry.toml`)
- Solidity version: 0.8.28
- Optimizer runs: 10,000
- EVM version: Cancun
- Custom source path: `src/contracts`
- Test path: `test`

### Import Remappings (`remappings.txt`)
- Privacy pool core contracts via submodule
- Account abstraction contracts via npm
- OpenZeppelin contracts for utilities
- Custom remapping for project contracts: `privacy-pool-paymasters-contracts/=src/contracts`

### Development Notes
- **Hybrid Build System**: Uses both Foundry (primary) and Hardhat (TypeScript support)
- **Circuit Dependencies**: Pre-built circuit artifacts required for ZK proof generation
- **Mock Environment**: Docker-based AA environment with Anvil + Alto bundler for testing
- **Deterministic Smart Account**: Single expected account pattern for enhanced security and cost predictability
- **Gas Optimization**: High optimizer runs (10,000) for gas-efficient paymaster operations
- **Privacy Focus**: All operations maintain user anonymity through ZK membership proofs