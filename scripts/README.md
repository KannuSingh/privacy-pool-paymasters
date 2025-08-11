# Privacy Pool Modular Scripts for Base Sepolia

This directory contains three focused scripts that handle each phase of the Privacy Pool workflow independently. This modular approach allows for better testing, debugging, and realistic simulation of the Privacy Pool protocol.

## 🔧 Scripts Overview

### 1. **1-CreateDeposit-BaseSepolia.ts** - Deposit Creation
- **Purpose**: Creates new deposits in the Privacy Pool
- **Function**: Generates nullifier/secret, creates commitment, submits to blockchain
- **State**: Saves deposit with status "deposited"

### 2. **2-ApproveASP-BaseSepolia.ts** - ASP Management  
- **Purpose**: Updates Approved Set of Participants (ASP) 
- **Function**: Builds cumulative ASP tree, updates on-chain root
- **State**: Marks deposits as "asp_approved"

### 3. **3-Withdraw-BaseSepolia.ts** - Withdrawal Execution
- **Purpose**: Executes privacy-preserving withdrawals
- **Function**: Generates ZK proof, withdraws funds, handles change
- **State**: Creates new nullifier/secret for change output

## 🚀 Quick Start

### Prerequisites
```bash
# Set environment variables
export PRIVATE_KEY="0x..."
export PIMLICO_API_KEY="your-key"
```

### Basic Workflow
```bash
# 1. Create a deposit
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001

# 2. Approve the deposit in ASP
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts

# 3. Withdraw the deposit  
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 0
```

## 📊 State Management

All scripts share a common state file: `privacy-pool-secrets.json`

```json
{
  "deposits": [
    {
      "depositIndex": 0,
      "nullifier": "12345...",
      "secret": "67890...", 
      "commitment": "11111...",
      "label": "22222...",
      "amount": "1000000000000000",
      "status": "asp_approved",
      "transactionHash": "0x...",
      "blockNumber": "123456"
    }
  ],
  "aspHistory": [
    {
      "root": "33333...",
      "approvedLabels": ["22222...", "44444..."],
      "approvedDepositIndices": [0, 1],
      "transactionHash": "0x...",
      "blockNumber": "123457"
    }
  ],
  "withdrawals": [
    {
      "sourceDepositIndex": 0,
      "withdrawalAmount": "500000000000000",
      "changeAmount": "500000000000000", 
      "newNullifier": "55555...",
      "newSecret": "66666...",
      "transactionHash": "0x..."
    }
  ],
  "lastDepositIndex": 1
}
```

## 📝 Detailed Usage

### 1-CreateDeposit-BaseSepolia.ts

**Purpose**: Create new privacy pool deposits

```bash
# Default amount (0.001 ETH)
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts

# Custom amount
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.005

# Multiple deposits
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.002
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.003
```

**What it does**:
1. Generates random nullifier and secret
2. Computes precommitment = Poseidon(nullifier, secret)  
3. Submits deposit transaction with ETH value
4. Extracts label and commitment from deposit event
5. Saves all critical data with status "deposited"

**Output**:
- Deposit record in state file
- Transaction on Base Sepolia
- Critical secrets for future withdrawal

### 2-ApproveASP-BaseSepolia.ts

**Purpose**: Update Approved Set of Participants (ASP)

```bash
# Approve all pending deposits
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts

# Approve specific deposits  
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 0 1 2

# Check current state
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts --state
```

**What it does**:
1. Loads all deposits that need ASP approval
2. Builds cumulative ASP Merkle tree with all approved labels
3. Updates on-chain ASP root via updateRoot() call
4. Marks deposits as "asp_approved" status
5. Saves ASP history for future withdrawals

**Critical Feature**: ASP tree accumulates ALL approved labels across multiple runs, ensuring proper Merkle tree consistency.

### 3-Withdraw-BaseSepolia.ts

**Purpose**: Execute privacy-preserving withdrawals

```bash
# Full withdrawal of deposit 0
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 0

# Partial withdrawal (0.0005 ETH from deposit 1)
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 1 0.0005
```

**What it does**:
1. Validates deposit is ASP approved
2. Builds complete Merkle trees from ALL deposits and ASP state  
3. Generates new nullifier/secret for change output
4. Creates ZK withdrawal proof with complete trees
5. Executes withdrawal transaction
6. Creates change deposit if partial withdrawal
7. Updates deposit status to "withdrawn"

**Important**: Generates NEW nullifier and secret for change output, which becomes a new deposit that needs ASP approval.

## 🔄 Multi-Run Examples

### Example 1: Multiple Deposits + Batch ASP Approval

```bash
# Create 3 deposits
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001  # Deposit 0
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.002  # Deposit 1  
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.003  # Deposit 2

# Approve all at once (ASP contains all 3 labels)
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts

# Withdraw any deposit (proof uses complete anonymity set)
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 1
```

### Example 2: Incremental ASP Approvals

```bash
# Create and approve deposits incrementally
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 0          # ASP has 1 label

npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.002  
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 1          # ASP has 2 labels

npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.003
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 2          # ASP has 3 labels

# All withdrawals use complete ASP with 3 labels
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 0
```

### Example 3: Partial Withdrawals with Change

```bash
# Create large deposit
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.01

# Approve it
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 0

# Partial withdrawal (creates change)
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 0 0.005

# Result: 
# - 0.005 ETH withdrawn
# - 0.005 ETH change becomes new deposit with index 1
# - Change deposit needs ASP approval before withdrawal
```

## 🌳 Merkle Tree Consistency

**Critical Feature**: The scripts ensure perfect Merkle tree consistency across multiple runs:

1. **Deposit Tree**: Built from ALL deposits in order by depositIndex
2. **ASP Tree**: Accumulates ALL approved labels from all ASP updates
3. **Proof Generation**: Uses complete trees for maximum anonymity set

### Tree Building Process

```typescript
// Deposit tree includes ALL deposits
const allDeposits = state.deposits.sort((a, b) => a.depositIndex - b.depositIndex);
allDeposits.forEach(deposit => {
    depositTree.insert(BigInt(deposit.commitment));
});

// ASP tree includes ALL approved labels  
const allApprovedLabels = state.aspHistory
    .flatMap(asp => asp.approvedLabels)
    .map(label => BigInt(label));
allApprovedLabels.forEach(label => {
    aspTree.insert(label);
});
```

## 🔐 Secret Management

**Critical Secrets Stored**:
- **Nullifier**: For double-spend protection
- **Secret**: For commitment generation  
- **Commitment**: On-chain commitment hash
- **Label**: ASP participant identifier

**Change Output Handling**:
- Partial withdrawals generate NEW nullifier/secret
- Change becomes new deposit with incremented index
- Change deposits need ASP approval before withdrawal

## 🚨 Important Notes

1. **Backup secrets**: `privacy-pool-secrets.json` contains critical data for withdrawals
2. **Sequential workflow**: Deposits → ASP Approval → Withdrawal  
3. **Change handling**: Partial withdrawals create new deposits
4. **Tree consistency**: All proofs use complete historical state
5. **Mock proofs**: Withdrawal script uses mock ZK proofs for demonstration

## 🛠 Development

### Testing the Scripts

```bash
# Test deposit creation
npm run test:deposit

# Test ASP approval  
npm run test:asp

# Test withdrawal
npm run test:withdrawal

# Test complete workflow
npm run test:workflow
```

### State Inspection

```bash
# View current state
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts --state

# Or manually inspect
cat privacy-pool-secrets.json | jq
```

## 🔗 Contract Addresses (Base Sepolia)

- **Entrypoint**: `0x67992c861b7559FBB6F5B6d55Cc383472D80e0A5`
- **Privacy Pool**: `0xbBB978Ad37d847ffa1651900Ca75837212EBdf1f`
- **Paymaster**: `0x1D84295EA19D1EE44ECe18a098789494000aFc04`
- **Withdrawal Verifier**: `0x4A679253410272dd5232B3Ff7cF5dbB88f295319`

## 📖 References

- [Privacy Pool Specification](../spec.md)
- [State Management Documentation](../PRIVACY_POOL_STATE_MANAGEMENT.md)
- [Original E2E Script](./PaymasterE2E.ts)
