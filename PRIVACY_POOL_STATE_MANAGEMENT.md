# Privacy Pool State Management

## Overview

The modular Privacy Pool scripts maintain comprehensive state management that ensures **correct Merkle tree construction** across multiple script executions. This is critical for Privacy Pool protocol compliance.

## Key Components

### 1. **Persistent State Storage**

The scripts maintain complete state in `privacy-pool-secrets.json`:

```typescript
interface PrivacyPoolState {
    deposits: DepositRecord[];     // All deposit records with secrets
    aspHistory: ASPRecord[];       // All ASP updates
    withdrawals: WithdrawalRecord[]; // All withdrawal records
    lastDepositIndex: number;      // Track deposit ordering
}
```

### 2. **Complete Deposit Tree Construction**

**Problem Solved**: Previously, each run only used the current deposit for Merkle trees.

**Solution**: Now builds complete trees from ALL historical deposits:

```typescript
function buildDepositTree(deposits: DepositRecord[]): { tree: any; commitments: bigint[] } {
    const depositTree = new LeanIMT(hash);
    
    // Add ALL deposits in order
    deposits
        .sort((a, b) => a.depositIndex - b.depositIndex)
        .forEach((deposit) => {
            const commitment = BigInt(deposit.commitment);
            depositTree.insert(commitment);
        });
    
    return { tree: depositTree, commitments };
}
```

### 3. **Accumulative ASP Management**

**Problem Solved**: ASP tree was rebuilt with only current deposit each time.

**Solution**: ASP accumulates ALL approved participant labels:

```typescript
// Include ALL previous deposits in ASP
state.deposits.forEach((deposit) => {
    allLabels.push(BigInt(deposit.label));
});

// Build complete ASP tree
const aspTree = buildASPTree(allLabels);
```

### 4. **Deposit Index Tracking**

Each deposit gets a unique, sequential index:

```typescript
const state = loadPrivacyPoolState();
const nextDepositIndex = state.lastDepositIndex + 1;

// Save with proper index
saveDepositRecord({
    // ... other fields
    depositIndex: nextDepositIndex,
    amount: actualValue.toString(),
});
```

### 5. **ZK Proof Generation with Complete Trees**

**Critical Fix**: Proofs now use complete state trees:

```typescript
// Build complete deposit tree from ALL deposits
const state = loadPrivacyPoolState();
const { tree: depositTree, commitments } = buildDepositTree(state.deposits);

// Use ALL commitments and labels for proof
const withdrawalProof = await prover.generateWithdrawalProof({
    // ...
    stateTreeCommitments: commitments,        // ALL commitments
    aspTreeLabels: aspData.allLabels,        // ALL approved labels
});
```

## Modular Script Usage

### 1-CreateDeposit-BaseSepolia.ts
```bash
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts [amount_eth]
```
- Creates deposit + saves with "deposited" status

### 2-ApproveASP-BaseSepolia.ts
```bash
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts [deposit_indices...]
```
- Updates ASP with cumulative labels + marks deposits "asp_approved"

### 3-Withdraw-BaseSepolia.ts
```bash
npx ts-node scripts/3-Withdraw-BaseSepolia.ts <deposit_index> [amount_eth]
```
- Generates ZK proof with complete trees + executes withdrawal

## Multi-Run Workflow

### First Run
```bash
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001
```
**Result**: 
- `privacy-pool-secrets.json` created with 1 deposit
- Deposit tree with 1 commitment

### Second Run
```bash
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.002
```
**Result**:
- State updated with 2 deposits
- Next operations use complete trees with both deposits

### ASP Approval
```bash
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts
```
**Result**:
- ASP tree with both deposit labels
- Both deposits marked "asp_approved"

### Withdrawal
```bash
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 0
```
**Result**:
- Withdrawal proof uses complete trees with ALL deposits
- Proper Privacy Pool protocol compliance

## State File Structure

```json
{
  "deposits": [
    {
      "timestamp": "2025-08-10T...",
      "depositIndex": 0,
      "nullifier": "12345...",
      "secret": "67890...",
      "commitment": "22222...",
      "label": "33333...",
      "amount": "1000000000000000",
      "status": "asp_approved",
      "transactionHash": "0xabc...",
      "blockNumber": "123456"
    }
  ],
  "aspHistory": [
    {
      "timestamp": "2025-08-10T...",
      "root": "44444...",
      "approvedLabels": ["33333...", "55555..."],
      "approvedDepositIndices": [0, 1],
      "transactionHash": "0xdef...",
      "blockNumber": "123457"
    }
  ],
  "withdrawals": [
    {
      "sourceDepositIndex": 0,
      "withdrawalAmount": "500000000000000",
      "changeAmount": "500000000000000",
      "newNullifier": "77777...",
      "newSecret": "88888...",
      "transactionHash": "0xghi..."
    }
  ],
  "lastDepositIndex": 1
}
```

## Critical Benefits

1. **Merkle Tree Consistency**: Trees are built identically across runs
2. **Anonymity Set Growth**: Each deposit increases the anonymity set
3. **Withdrawal Flexibility**: Can withdraw from any approved deposit
4. **Protocol Compliance**: Follows Privacy Pool specification exactly
5. **State Recovery**: Complete state preserved across script executions
6. **Change Output Handling**: New nullifier/secret for partial withdrawals

## Example Multi-Run Session

```bash
# Start fresh
rm privacy-pool-secrets.json

# Create 3 deposits
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.001  # Deposit 0
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.002  # Deposit 1  
npx ts-node scripts/1-CreateDeposit-BaseSepolia.ts 0.003  # Deposit 2

# Approve all deposits (ASP includes all 3 labels)
npx ts-node scripts/2-ApproveASP-BaseSepolia.ts

# Withdraw with complete anonymity set
npx ts-node scripts/3-Withdraw-BaseSepolia.ts 1
```

This ensures that **every ZK proof is generated with the complete, accurate Merkle trees** needed for proper Privacy Pool protocol compliance.
